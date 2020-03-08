`include "VX_cache_config.v"

module VX_cache_dram_req_arb
	#(
	// Size of cache in bytes
	parameter CACHE_SIZE_BYTES              = 1024, 
	// Size of line inside a bank in bytes
	parameter BANK_LINE_SIZE_BYTES          = 16, 
	// Number of banks {1, 2, 4, 8,...}
	parameter NUMBER_BANKS                  = 8, 
	// Size of a word in bytes
	parameter WORD_SIZE_BYTES               = 4, 
	// Number of Word requests per cycle {1, 2, 4, 8, ...}
	parameter NUMBER_REQUESTS               = 2, 
	// Number of cycles to complete stage 1 (read from memory)
	parameter STAGE_1_CYCLES                = 2, 

// Queues feeding into banks Knobs {1, 2, 4, 8, ...}

	// Core Request Queue Size
	parameter REQQ_SIZE                     = 8, 
	// Miss Reserv Queue Knob
	parameter MRVQ_SIZE                     = 8, 
	// Dram Fill Rsp Queue Size
	parameter DFPQ_SIZE                     = 2, 
	// Snoop Req Queue
	parameter SNRQ_SIZE                     = 8, 

// Queues for writebacks Knobs {1, 2, 4, 8, ...}
	// Core Writeback Queue Size
	parameter CWBQ_SIZE                     = 8, 
	// Dram Writeback Queue Size
	parameter DWBQ_SIZE                     = 4, 
	// Dram Fill Req Queue Size
	parameter DFQQ_SIZE                     = 8, 
	// Lower Level Cache Hit Queue Size
	parameter LLVQ_SIZE                     = 16, 

 	// Fill Invalidator Size {Fill invalidator must be active}
 	parameter FILL_INVALIDAOR_SIZE          = 16, 

// Dram knobs
	parameter SIMULATED_DRAM_LATENCY_CYCLES = 10


	)
	(
	input  wire clk,
	input  wire reset,


	// Fill Request
    output wire                                             dfqq_full,
    input  wire[NUMBER_BANKS-1:0]                          per_bank_dram_fill_req,
    input  wire[NUMBER_BANKS-1:0][31:0]                    per_bank_dram_fill_req_addr,

    // DFQ Request
    output wire[NUMBER_BANKS-1:0]                            per_bank_dram_wb_queue_pop,
    input  wire[NUMBER_BANKS-1:0]                            per_bank_dram_wb_req,
    input  wire[NUMBER_BANKS-1:0][31:0]                      per_bank_dram_wb_req_addr,
    input  wire[NUMBER_BANKS-1:0][`BANK_LINE_SIZE_RNG][31:0] per_bank_dram_wb_req_data,
    input  wire[NUMBER_BANKS-1:0]                            per_bank_dram_because_of_snp,

    // real Dram request
    output wire                                             dram_req,
    output wire                                             dram_req_write,
    output wire                                             dram_req_read,
    output wire [31:0]                                      dram_req_addr,
    output wire [31:0]                                      dram_req_size,
    output wire [`BANK_LINE_SIZE_RNG][31:0]                 dram_req_data,
    output wire                                             dram_req_because_of_wb
	
);

	wire dfqq_req;
	wire[31:0] dfqq_req_addr;
	wire dfqq_empty;
	wire dwb_valid;
	wire dfqq_pop  = !dwb_valid && dfqq_req; // If no dwb, and dfqq has valids, then pop
	wire dfqq_push = (|per_bank_dram_fill_req);

	VX_cache_dfq_queue VX_cache_dfq_queue(
		.clk                        (clk),
		.reset                      (reset),
		.dfqq_push                  (dfqq_push),
		.per_bank_dram_fill_req     (per_bank_dram_fill_req),
		.per_bank_dram_fill_req_addr(per_bank_dram_fill_req_addr),
		.dfqq_pop                   (dfqq_pop),
		.dfqq_req                   (dfqq_req),
		.dfqq_req_addr              (dfqq_req_addr),
		.dfqq_empty                 (dfqq_empty),
		.dfqq_full                  (dfqq_full)
		);

	wire[`vx_clog2(NUMBER_BANKS)-1:0] dwb_bank;
	wire[NUMBER_BANKS-1:0]            use_wb_valid = per_bank_dram_wb_req | per_bank_dram_because_of_snp;
	VX_generic_priority_encoder #(.N(NUMBER_BANKS)) VX_sel_dwb(
		.valids(use_wb_valid),
		.index (dwb_bank),
		.found (dwb_valid)
		);


	assign per_bank_dram_wb_queue_pop = per_bank_dram_wb_req & ((1 << dwb_bank));


	assign dram_req               = dwb_valid || dfqq_req;
	assign dram_req_write         = dwb_valid;
	assign dram_req_read          = dfqq_req && !dwb_valid;
	assign dram_req_addr          = (dwb_valid ? per_bank_dram_wb_req_addr[dwb_bank] : dfqq_req_addr) & `BASE_ADDR_MASK;
	assign dram_req_size          = BANK_LINE_SIZE_BYTES;
	assign dram_req_data          = dwb_valid ? per_bank_dram_wb_req_data[dwb_bank] : 0;
	assign dram_req_because_of_wb = dwb_valid ? per_bank_dram_because_of_snp[dwb_bank] : 0;

endmodule