`include "VX_define.vh"

module VX_dmem_ctrl (
    input wire               clk,
    input wire               reset,

    // Dram <-> Dcache
    VX_cache_dram_req_if cache_dram_req_if,
    VX_cache_dram_rsp_if cache_dram_rsp_if,
    VX_cache_snp_req_rsp_if     gpu_dcache_snp_req_if,

    // Dram <-> Icache
    VX_cache_dram_req_if gpu_icache_dram_req_if,
    VX_cache_dram_rsp_if gpu_icache_dram_rsp_if,
    VX_cache_snp_req_rsp_if     gpu_icache_snp_req_if,

    // Core <-> Dcache
    VX_cache_core_rsp_if  dcache_rsp_if,
    VX_cache_core_req_if  dcache_req_if,

    // Core <-> Icache
    VX_cache_core_rsp_if  icache_rsp_if,
    VX_cache_core_req_if  icache_req_if
);

    VX_cache_core_req_if   #(.NUM_REQUESTS(`DNUM_REQUESTS))   dcache_req_smem_if();
    VX_cache_core_rsp_if   #(.NUM_REQUESTS(`DNUM_REQUESTS))   dcache_rsp_smem_if();
    
    VX_cache_core_req_if   #(.NUM_REQUESTS(`DNUM_REQUESTS))   dcache_req_dcache_if();
    VX_cache_core_rsp_if   #(.NUM_REQUESTS(`DNUM_REQUESTS))   dcache_rsp_dcache_if();

    wire to_shm          = dcache_req_if.core_req_addr[0][31:24] == 8'hFF;
    wire dcache_wants_wb = (|dcache_rsp_dcache_if.core_rsp_valid);

    // Dcache Request
    assign dcache_req_dcache_if.core_req_valid       = dcache_req_if.core_req_valid & {`NUM_THREADS{~to_shm}};
    assign dcache_req_dcache_if.core_req_read        = dcache_req_if.core_req_read;
    assign dcache_req_dcache_if.core_req_write       = dcache_req_if.core_req_write;
    assign dcache_req_dcache_if.core_req_addr        = dcache_req_if.core_req_addr;    
    assign dcache_req_dcache_if.core_req_data        = dcache_req_if.core_req_data;    
    assign dcache_req_dcache_if.core_req_rd          = dcache_req_if.core_req_rd;
    assign dcache_req_dcache_if.core_req_wb          = dcache_req_if.core_req_wb;
    assign dcache_req_dcache_if.core_req_warp_num    = dcache_req_if.core_req_warp_num;
    assign dcache_req_dcache_if.core_req_pc          = dcache_req_if.core_req_pc;

    assign dcache_rsp_dcache_if.core_rsp_ready       = dcache_rsp_if.core_rsp_ready;    
    
    // Shared Memory Request
    assign dcache_req_smem_if.core_req_valid       = dcache_req_if.core_req_valid & {`NUM_THREADS{to_shm}};
    assign dcache_req_smem_if.core_req_addr        = dcache_req_if.core_req_addr;
    assign dcache_req_smem_if.core_req_data        = dcache_req_if.core_req_data;
    assign dcache_req_smem_if.core_req_read        = dcache_req_if.core_req_read;
    assign dcache_req_smem_if.core_req_write       = dcache_req_if.core_req_write;
    assign dcache_req_smem_if.core_req_rd          = dcache_req_if.core_req_rd;
    assign dcache_req_smem_if.core_req_wb          = dcache_req_if.core_req_wb;
    assign dcache_req_smem_if.core_req_warp_num    = dcache_req_if.core_req_warp_num;
    assign dcache_req_smem_if.core_req_pc          = dcache_req_if.core_req_pc;

    assign dcache_rsp_smem_if.core_rsp_ready       = dcache_rsp_if.core_rsp_ready && ~dcache_wants_wb;    

    // Dcache Response
    assign dcache_rsp_if.core_rsp_valid     = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_valid    : dcache_rsp_smem_if.core_rsp_valid;
    assign dcache_rsp_if.core_rsp_read      = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_read   : dcache_rsp_smem_if.core_rsp_read;
    assign dcache_rsp_if.core_rsp_write     = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_write   : dcache_rsp_smem_if.core_rsp_write;
    assign dcache_rsp_if.core_rsp_pc        = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_pc       : dcache_rsp_smem_if.core_rsp_pc;    
    assign dcache_rsp_if.core_rsp_data      = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_data : dcache_rsp_smem_if.core_rsp_data;
    assign dcache_rsp_if.core_rsp_warp_num  = dcache_wants_wb ? dcache_rsp_dcache_if.core_rsp_warp_num : dcache_rsp_smem_if.core_rsp_warp_num;

    assign dcache_req_if.core_req_ready     = to_shm ? dcache_req_smem_if.core_req_ready : dcache_req_dcache_if.core_req_ready;

    VX_cache_dram_req_if #(.BANK_LINE_WORDS(`DBANK_LINE_WORDS)) gpu_smem_dram_req_if();
    VX_cache_dram_rsp_if #(.BANK_LINE_WORDS(`DBANK_LINE_WORDS)) gpu_smem_dram_rsp_if();

    VX_cache #(
        .CACHE_SIZE_BYTES             (`SCACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES         (`SBANK_LINE_SIZE_BYTES),
        .NUM_BANKS                    (`SNUM_BANKS),
        .WORD_SIZE_BYTES              (`SWORD_SIZE_BYTES),
        .NUM_REQUESTS                 (`SNUM_REQUESTS),
        .STAGE_1_CYCLES               (`SSTAGE_1_CYCLES),
        .FUNC_ID                      (`SFUNC_ID),
        .REQQ_SIZE                    (`SREQQ_SIZE),
        .MRVQ_SIZE                    (`SMRVQ_SIZE),
        .DFPQ_SIZE                    (`SDFPQ_SIZE),
        .SNRQ_SIZE                    (`SSNRQ_SIZE),
        .CWBQ_SIZE                    (`SCWBQ_SIZE),
        .DWBQ_SIZE                    (`SDWBQ_SIZE),
        .DFQQ_SIZE                    (`SDFQQ_SIZE),
        .LLVQ_SIZE                    (`SLLVQ_SIZE),
        .FFSQ_SIZE                    (`SFFSQ_SIZE),
        .PRFQ_SIZE                    (`SPRFQ_SIZE),
        .PRFQ_STRIDE                  (`SPRFQ_STRIDE),
        .FILL_INVALIDAOR_SIZE         (`SFILL_INVALIDAOR_SIZE),
        .SIMULATED_DRAM_LATENCY_CYCLES(`SSIMULATED_DRAM_LATENCY_CYCLES)
    ) gpu_smem (
        .clk                (clk),
        .reset              (reset),

        // Core req
        .core_req_valid     (dcache_req_smem_if.core_req_valid),
        .core_req_read      (dcache_req_smem_if.core_req_read),
        .core_req_write     (dcache_req_smem_if.core_req_write),
        .core_req_addr      (dcache_req_smem_if.core_req_addr),
        .core_req_data      (dcache_req_smem_if.core_req_data),        
        .core_req_rd        (dcache_req_smem_if.core_req_rd),
        .core_req_wb        (dcache_req_smem_if.core_req_wb),
        .core_req_warp_num  (dcache_req_smem_if.core_req_warp_num),
        .core_req_pc        (dcache_req_smem_if.core_req_pc),

        // Can submit core Req
        .core_req_ready     (dcache_req_smem_if.core_req_ready),

        // Core Cache Can't WB
        .core_rsp_ready     (dcache_rsp_smem_if.core_rsp_ready),

        // Cache CWB
        .core_rsp_valid     (dcache_rsp_smem_if.core_rsp_valid),
        .core_rsp_read      (dcache_rsp_smem_if.core_rsp_read),
        .core_rsp_write     (dcache_rsp_smem_if.core_rsp_write),
        .core_rsp_warp_num  (dcache_rsp_smem_if.core_rsp_warp_num),
        .core_rsp_data      (dcache_rsp_smem_if.core_rsp_data),
        .core_rsp_pc        (dcache_rsp_smem_if.core_rsp_pc),
    `IGNORE_WARNINGS_BEGIN
        .core_rsp_addr   (),
    `IGNORE_WARNINGS_END

        // DRAM response
        .dram_rsp_valid     (gpu_smem_dram_rsp_if.dram_rsp_valid),
        .dram_rsp_addr      (gpu_smem_dram_rsp_if.dram_rsp_addr),
        .dram_rsp_data      (gpu_smem_dram_rsp_if.dram_rsp_data),

        // DRAM accept response
        .dram_rsp_ready     (gpu_smem_dram_req_if.dram_rsp_ready),

        // DRAM Req
        .dram_req_read      (gpu_smem_dram_req_if.dram_req_read),
        .dram_req_write     (gpu_smem_dram_req_if.dram_req_write),        
        .dram_req_addr      (gpu_smem_dram_req_if.dram_req_addr),
        .dram_req_data      (gpu_smem_dram_req_if.dram_req_data),
        .dram_req_ready     (0),

        // Snoop Request
        .snp_req_valid      (0),
        .snp_req_addr       (0),
    `IGNORE_WARNINGS_BEGIN
        .snp_req_ready      (),
    `IGNORE_WARNINGS_END

        // Snoop Forward
    `IGNORE_WARNINGS_BEGIN
        .snp_fwd_valid      (),
        .snp_fwd_addr       (),
    `IGNORE_WARNINGS_END
        .snp_fwd_ready      (0)
    );

    VX_cache #(
        .CACHE_SIZE_BYTES             (`DCACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES         (`DBANK_LINE_SIZE_BYTES),
        .NUM_BANKS                    (`DNUM_BANKS),
        .WORD_SIZE_BYTES              (`DWORD_SIZE_BYTES),
        .NUM_REQUESTS                 (`DNUM_REQUESTS),
        .STAGE_1_CYCLES               (`DSTAGE_1_CYCLES),
        .FUNC_ID                      (`DFUNC_ID),
        .REQQ_SIZE                    (`DREQQ_SIZE),
        .MRVQ_SIZE                    (`DMRVQ_SIZE),
        .DFPQ_SIZE                    (`DDFPQ_SIZE),
        .SNRQ_SIZE                    (`DSNRQ_SIZE),
        .CWBQ_SIZE                    (`DCWBQ_SIZE),
        .DWBQ_SIZE                    (`DDWBQ_SIZE),
        .DFQQ_SIZE                    (`DDFQQ_SIZE),
        .LLVQ_SIZE                    (`DLLVQ_SIZE),
        .FFSQ_SIZE                    (`DFFSQ_SIZE),
        .PRFQ_SIZE                    (`DPRFQ_SIZE),
        .PRFQ_STRIDE                  (`DPRFQ_STRIDE),
        .FILL_INVALIDAOR_SIZE         (`DFILL_INVALIDAOR_SIZE),
        .SIMULATED_DRAM_LATENCY_CYCLES(`DSIMULATED_DRAM_LATENCY_CYCLES)
    ) gpu_dcache (
        .clk                (clk),
        .reset              (reset),

        // Core req
        .core_req_valid     (dcache_req_dcache_if.core_req_valid),
        .core_req_read      (dcache_req_dcache_if.core_req_read),
        .core_req_write     (dcache_req_dcache_if.core_req_write),
        .core_req_addr      (dcache_req_dcache_if.core_req_addr),
        .core_req_data      (dcache_req_dcache_if.core_req_data),        
        .core_req_rd        (dcache_req_dcache_if.core_req_rd),
        .core_req_wb        (dcache_req_dcache_if.core_req_wb),
        .core_req_warp_num  (dcache_req_dcache_if.core_req_warp_num),
        .core_req_pc        (dcache_req_dcache_if.core_req_pc),

        // Can submit core Req
        .core_req_ready     (dcache_req_dcache_if.core_req_ready),

        // Core Cache Can't WB
        .core_rsp_ready     (dcache_rsp_dcache_if.core_rsp_ready),

        // Cache CWB
        .core_rsp_valid     (dcache_rsp_dcache_if.core_rsp_valid),
        .core_rsp_read      (dcache_rsp_dcache_if.core_rsp_read),
        .core_rsp_write     (dcache_rsp_dcache_if.core_rsp_write),
        .core_rsp_warp_num  (dcache_rsp_dcache_if.core_rsp_warp_num),
        .core_rsp_data      (dcache_rsp_dcache_if.core_rsp_data),
        .core_rsp_pc        (dcache_rsp_dcache_if.core_rsp_pc),
    `IGNORE_WARNINGS_BEGIN
        .core_rsp_addr   (),
    `IGNORE_WARNINGS_END

        // DRAM response
        .dram_rsp_valid     (cache_dram_rsp_if.dram_rsp_valid),
        .dram_rsp_addr      (cache_dram_rsp_if.dram_rsp_addr),
        .dram_rsp_data      (cache_dram_rsp_if.dram_rsp_data),

        // DRAM accept response
        .dram_rsp_ready     (cache_dram_req_if.dram_rsp_ready),

        // DRAM Req
        .dram_req_read      (cache_dram_req_if.dram_req_read),
        .dram_req_write     (cache_dram_req_if.dram_req_write),        
        .dram_req_addr      (cache_dram_req_if.dram_req_addr),
        .dram_req_data      (cache_dram_req_if.dram_req_data),
        .dram_req_ready     (cache_dram_req_if.dram_req_ready),

        // Snoop Request
        .snp_req_valid      (gpu_dcache_snp_req_if.snp_req_valid),
        .snp_req_addr       (gpu_dcache_snp_req_if.snp_req_addr),
        .snp_req_ready      (gpu_dcache_snp_req_if.snp_req_ready),

        // Snoop Forward
    `IGNORE_WARNINGS_BEGIN
        .snp_fwd_valid      (),
        .snp_fwd_addr       (),
    `IGNORE_WARNINGS_END
        .snp_fwd_ready      (0)
    );

    VX_cache #(
        .CACHE_SIZE_BYTES             (`ICACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES         (`IBANK_LINE_SIZE_BYTES),
        .NUM_BANKS                    (`INUM_BANKS),
        .WORD_SIZE_BYTES              (`IWORD_SIZE_BYTES),
        .NUM_REQUESTS                 (`INUM_REQUESTS),
        .STAGE_1_CYCLES               (`ISTAGE_1_CYCLES),
        .FUNC_ID                      (`IFUNC_ID),
        .REQQ_SIZE                    (`IREQQ_SIZE),
        .MRVQ_SIZE                    (`IMRVQ_SIZE),
        .DFPQ_SIZE                    (`IDFPQ_SIZE),
        .SNRQ_SIZE                    (`ISNRQ_SIZE),
        .CWBQ_SIZE                    (`ICWBQ_SIZE),
        .DWBQ_SIZE                    (`IDWBQ_SIZE),
        .DFQQ_SIZE                    (`IDFQQ_SIZE),
        .LLVQ_SIZE                    (`ILLVQ_SIZE),
        .FFSQ_SIZE                    (`IFFSQ_SIZE),
        .PRFQ_SIZE                    (`IPRFQ_SIZE),
        .PRFQ_STRIDE                  (`IPRFQ_STRIDE),
        .FILL_INVALIDAOR_SIZE         (`IFILL_INVALIDAOR_SIZE),
        .SIMULATED_DRAM_LATENCY_CYCLES(`ISIMULATED_DRAM_LATENCY_CYCLES)
    ) gpu_icache (
        .clk                   (clk),
        .reset                 (reset),

        // Core req
        .core_req_valid        (icache_req_if.core_req_valid),
        .core_req_read         (icache_req_if.core_req_read),
        .core_req_write        (icache_req_if.core_req_write),
        .core_req_addr         (icache_req_if.core_req_addr),
        .core_req_data         (icache_req_if.core_req_data),        
        .core_req_rd           (icache_req_if.core_req_rd),
        .core_req_wb           (icache_req_if.core_req_wb),
        .core_req_warp_num     (icache_req_if.core_req_warp_num),
        .core_req_pc           (icache_req_if.core_req_pc),

        // Can submit core Req
        .core_req_ready        (icache_req_if.core_req_ready),

        // Core Cache Can't WB
        .core_rsp_ready        (icache_rsp_if.core_rsp_ready),

        // Cache CWB
        .core_rsp_valid        (icache_rsp_if.core_rsp_valid),
        .core_rsp_read         (icache_rsp_if.core_rsp_read),
        .core_rsp_write        (icache_rsp_if.core_rsp_write),
        .core_rsp_warp_num     (icache_rsp_if.core_rsp_warp_num),
        .core_rsp_data         (icache_rsp_if.core_rsp_data),
        .core_rsp_pc           (icache_rsp_if.core_rsp_pc),
    `IGNORE_WARNINGS_BEGIN
        .core_rsp_addr         (),
    `IGNORE_WARNINGS_END

        // DRAM response
        .dram_rsp_valid        (gpu_icache_dram_rsp_if.dram_rsp_valid),
        .dram_rsp_addr         (gpu_icache_dram_rsp_if.dram_rsp_addr),
        .dram_rsp_data         (gpu_icache_dram_rsp_if.dram_rsp_data),

        // DRAM accept response
        .dram_rsp_ready        (gpu_icache_dram_req_if.dram_rsp_ready),

        // DRAM Req
        .dram_req_read         (gpu_icache_dram_req_if.dram_req_read),
        .dram_req_write        (gpu_icache_dram_req_if.dram_req_write),        
        .dram_req_addr         (gpu_icache_dram_req_if.dram_req_addr),
        .dram_req_data         (gpu_icache_dram_req_if.dram_req_data),
        .dram_req_ready        (gpu_icache_dram_req_if.dram_req_ready),

        // Snoop Request
        .snp_req_valid         (gpu_icache_snp_req_if.snp_req_valid),
        .snp_req_addr          (gpu_icache_snp_req_if.snp_req_addr),
        .snp_req_ready         (gpu_icache_snp_req_if.snp_req_ready),

        // Snoop Forward
    `IGNORE_WARNINGS_BEGIN
        .snp_fwd_valid         (),
        .snp_fwd_addr          (),
    `IGNORE_WARNINGS_END
        .snp_fwd_ready         (0)
    );

endmodule
