#include <vx_spawn.h>
#include <vx_intrinsics.h>
#include <inttypes.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NUM_CORES_MAX 32

#define MIN(a, b) ((a) < (b) ? (a) : (b))

typedef struct {
	pfn_callback callback;
	const void * args;
	int offset;
	int N;
	int R;
} wspawn_tasks_args_t;

typedef struct {
  struct context_t * ctx;
  pfn_workgroup_func wg_func;
  const void * args;
  int  offset; 
  int  N;
  int  R;  
  char isXYpow2;
  char isXpow2;
  char log2XY;
  char log2X;
} wspawn_kernel_args_t;

void* g_wspawn_args[NUM_CORES_MAX];

inline char is_log2(int x) {
  return ((x & (x-1)) == 0);
}

inline int fast_log2(int x) {
  float f = x;
  return (*(int*)(&f)>>23) - 127;
}

static void spawn_tasks_callback() {  
  vx_tmc(vx_num_threads());

  int core_id = vx_core_id();
  int wid     = vx_warp_id();
  int tid     = vx_thread_id(); 
  int NT      = vx_num_threads();
  
  wspawn_tasks_args_t* p_wspawn_args = (wspawn_tasks_args_t*)g_wspawn_args[core_id];

  int wK = (p_wspawn_args->N * wid) + MIN(p_wspawn_args->R, wid);
  int tK = p_wspawn_args->N + (wid < p_wspawn_args->R);
  int offset = p_wspawn_args->offset + (wK * NT) + (tid * tK);

  for (int task_id = offset, N = task_id + tK; task_id < N; ++task_id) {
    (p_wspawn_args->callback)(task_id, p_wspawn_args->args);
  }

  vx_tmc(0 == wid);
}

void spawn_remaining_tasks_callback(int nthreads) {    
  vx_tmc(nthreads);

  int core_id = vx_core_id(); 
  int tid = vx_thread_gid();

  wspawn_tasks_args_t* p_wspawn_args = (wspawn_tasks_args_t*)g_wspawn_args[core_id];

  int task_id = p_wspawn_args->offset + tid;
  (p_wspawn_args->callback)(task_id, p_wspawn_args->args);

  vx_tmc(1);
}

void vx_spawn_tasks(int num_tasks, pfn_callback callback , const void * args) {
	// device specs
  int NC = vx_num_cores();
  int NW = vx_num_warps();
  int NT = vx_num_threads();

  // current core id
  int core_id = vx_core_id();  
  if (core_id >= NUM_CORES_MAX)
    return;

  // calculate necessary active cores
  int WT = NW * NT;
  int nC = (num_tasks > WT) ? (num_tasks / WT) : 1;
  int nc = MIN(nC, NC);
  if (core_id >= nc)
    return; // terminate extra cores

  // number of tasks per core
  int tasks_per_core = num_tasks / nc;
  int tasks_per_core0 = tasks_per_core;  
  if (core_id == (NC-1)) {    
    int QC_r = num_tasks - (nc * tasks_per_core0); 
    tasks_per_core0 += QC_r; // last core executes remaining tasks
  }

  // number of tasks per warp
  int nW = tasks_per_core0 / NT;        		// total warps per core
  int rT = tasks_per_core0 - (nW * NT); 		// remaining threads
  int fW  = (nW >= NW) ? (nW / NW) : 0;			// full warps iterations
  int rW  = (fW != 0) ? (nW - fW * NW) : 0; // remaining warps
  if (0 == fW)
    fW = 1;

  //--
  wspawn_tasks_args_t wspawn_args = { callback, args, core_id * tasks_per_core, fW, rW };
  g_wspawn_args[core_id] = &wspawn_args;

  //--
	if (nW >= 1)	{ 
    int nw = MIN(nW, NW);    
	  vx_wspawn(nw, spawn_tasks_callback);
    spawn_tasks_callback();
	}  

  //--    
  if (rT != 0) {
    wspawn_args.offset = tasks_per_core0 - rT;
    spawn_remaining_tasks_callback(rT);
  }
}

///////////////////////////////////////////////////////////////////////////////

static void spawn_kernel_callback() {  
  vx_tmc(vx_num_threads());

  int core_id = vx_core_id();
  int wid     = vx_warp_id();
  int tid     = vx_thread_id(); 
  int NT      = vx_num_threads();
  
  wspawn_kernel_args_t* p_wspawn_args = (wspawn_kernel_args_t*)g_wspawn_args[core_id];

  int wK = (p_wspawn_args->N * wid) + MIN(p_wspawn_args->R, wid);
  int tK = p_wspawn_args->N + (wid < p_wspawn_args->R);
  int offset = p_wspawn_args->offset + (wK * NT) + (tid * tK);

  int X = p_wspawn_args->ctx->num_groups[0];
  int Y = p_wspawn_args->ctx->num_groups[1];
  int XY = X * Y;

  for (int wg_id = offset, N = wg_id + tK; wg_id < N; ++wg_id) {    
    int k = p_wspawn_args->isXYpow2 ? (wg_id >> p_wspawn_args->log2XY) : (wg_id / XY);
    int wg_2d = wg_id - k * XY;
    int j = p_wspawn_args->isXpow2 ? (wg_2d >> p_wspawn_args->log2X) : (wg_2d / X);
    int i = wg_2d - j * X;

    int gid0 = p_wspawn_args->ctx->global_offset[0] + i;
    int gid1 = p_wspawn_args->ctx->global_offset[1] + j;
    int gid2 = p_wspawn_args->ctx->global_offset[2] + k;

    (p_wspawn_args->wg_func)(p_wspawn_args->args, p_wspawn_args->ctx, gid0, gid1, gid2);
  }

  vx_tmc(0 == wid);
}

static void spawn_kernel_remaining_callback(int nthreads) {    
  vx_tmc(nthreads);

  int core_id = vx_core_id(); 
  int tid = vx_thread_gid();

  wspawn_kernel_args_t* p_wspawn_args = (wspawn_kernel_args_t*)g_wspawn_args[core_id];

  int wg_id = p_wspawn_args->offset + tid;

  int X = p_wspawn_args->ctx->num_groups[0];
  int Y = p_wspawn_args->ctx->num_groups[1];
  int XY = X * Y;
  
  int k = p_wspawn_args->isXYpow2 ? (wg_id >> p_wspawn_args->log2XY) : (wg_id / XY);
  int wg_2d = wg_id - k * XY;
  int j = p_wspawn_args->isXpow2 ? (wg_2d >> p_wspawn_args->log2X) : (wg_2d / X);
  int i = wg_2d - j * X;

  int gid0 = p_wspawn_args->ctx->global_offset[0] + i;
  int gid1 = p_wspawn_args->ctx->global_offset[1] + j;
  int gid2 = p_wspawn_args->ctx->global_offset[2] + k;

  (p_wspawn_args->wg_func)(p_wspawn_args->args, p_wspawn_args->ctx, gid0, gid1, gid2);

  vx_tmc(1);
}

void vx_spawn_kernel(struct context_t * ctx, pfn_workgroup_func wg_func, const void * args) {  
  // total number of WGs
  int X  = ctx->num_groups[0];
  int Y  = ctx->num_groups[1];
  int Z  = ctx->num_groups[2];
  int XY = X * Y;
  int Q  = XY * Z;
  
  // device specs
  int NC = vx_num_cores();
  int NW = vx_num_warps();
  int NT = vx_num_threads();

  // current core id
  int core_id = vx_core_id();  
  if (core_id >= NUM_CORES_MAX)
    return;

  // calculate necessary active cores
  int WT = NW * NT;
  int nC = (Q > WT) ? (Q / WT) : 1;
  int nc = MIN(nC, NC);
  if (core_id >= nc)
    return; // terminate extra cores

  // number of workgroups per core
  int wgs_per_core = Q / nc;
  int wgs_per_core0 = wgs_per_core;  
  if (core_id == (NC-1)) {    
    int QC_r = Q - (nc * wgs_per_core0); 
    wgs_per_core0 += QC_r; // last core executes remaining WGs
  }

  // number of workgroups per warp
  int nW = wgs_per_core0 / NT;              // total warps per core
  int rT = wgs_per_core0 - (nW * NT);       // remaining threads
  int fW = (nW >= NW) ? (nW / NW) : 0;      // full warps iterations
  int rW = (fW != 0) ? (nW - fW * NW) : 0;  // reamining full warps
  if (0 == fW)
    fW = 1;

  // fast path handling
  char isXYpow2 = is_log2(XY);
  char isXpow2  = is_log2(X);
  char log2XY   = fast_log2(XY);
  char log2X    = fast_log2(X);

  //--
  wspawn_kernel_args_t wspawn_args = { ctx, wg_func, args, core_id * wgs_per_core, fW, rW, isXYpow2, isXpow2, log2XY, log2X };
  g_wspawn_args[core_id] = &wspawn_args;

  //--
	if (nW >= 1)	{ 
    int nw = MIN(nW, NW);    
	  vx_wspawn(nw, spawn_kernel_callback);
    spawn_kernel_callback();
	}  

  //--    
  if (rT != 0) {
    wspawn_args.offset = wgs_per_core0 - rT;
    spawn_kernel_remaining_callback(rT);
  }
}

#ifdef __cplusplus
}
#endif