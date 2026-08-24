`timescale 1ns/1ps

// Full-chip structural SXM wrapper.
// Hemisphere 0 (low packed slices) is West; hemisphere 1 (high packed
// slices) is East. Hemisphere identity is independent of the East/West stream
// direction encoded in each native SR selector.
module sxm_full (
    input  wire          clk_i,
    input  wire          rst_ni,

    input  wire [1:0]    transpose_cmd_valid_i,
    input  wire [191:0]  transpose_cmd_i,
    input  wire [1:0]    permute_cmd_valid_i,
    input  wire [191:0]  permute_cmd_i,

    output wire [767:0]  sr_read_req_o,
    input  wire [127:0]  sr_read_valid_i,
    input  wire [8191:0] sr_read_data_i,
    output wire [127:0]  sr_consume_o,

    output wire [127:0]  sr_write_valid_o,
    output wire [191:0]  sr_write_sel_o,
    output wire [8191:0] sr_write_data_o,

    output wire [1:0]    fault_valid_o,
    output wire [7:0]    transpose_input_invalid_o,
    output wire [7:0]    transpose_buffer_full_o,
    output wire [1:0]    permute_phase_fault_o,
    output wire [1:0]    permute_selector_fault_o,
    output wire [1:0]    permute_buffer_not_ready_o,
    output wire [1:0]    busy_o
);

    // Hemisphere 0: West hemisphere, always packed in the low slice.
    sxm_slice u_west_slice (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .transpose_cmd_valid_i(transpose_cmd_valid_i[0]),
        .transpose_cmd_i(transpose_cmd_i[0 +: 96]),
        .permute_cmd_valid_i(permute_cmd_valid_i[0]),
        .permute_cmd_i(permute_cmd_i[0 +: 96]),
        .sr_read_req_o(sr_read_req_o[0 +: 384]),
        .sr_read_valid_i(sr_read_valid_i[0 +: 64]),
        .sr_read_data_i(sr_read_data_i[0 +: 4096]),
        .sr_consume_o(sr_consume_o[0 +: 64]),
        .sr_write_valid_o(sr_write_valid_o[0 +: 64]),
        .sr_write_sel_o(sr_write_sel_o[0 +: 96]),
        .sr_write_data_o(sr_write_data_o[0 +: 4096]),
        .fault_valid_o(fault_valid_o[0]),
        .transpose_input_invalid_o(transpose_input_invalid_o[0 +: 4]),
        .transpose_buffer_full_o(transpose_buffer_full_o[0 +: 4]),
        .permute_phase_fault_o(permute_phase_fault_o[0]),
        .permute_selector_fault_o(permute_selector_fault_o[0]),
        .permute_buffer_not_ready_o(permute_buffer_not_ready_o[0]),
        .busy_o(busy_o[0])
    );

    // Hemisphere 1: East hemisphere, always packed in the high slice.
    sxm_slice u_east_slice (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .transpose_cmd_valid_i(transpose_cmd_valid_i[1]),
        .transpose_cmd_i(transpose_cmd_i[96 +: 96]),
        .permute_cmd_valid_i(permute_cmd_valid_i[1]),
        .permute_cmd_i(permute_cmd_i[96 +: 96]),
        .sr_read_req_o(sr_read_req_o[384 +: 384]),
        .sr_read_valid_i(sr_read_valid_i[64 +: 64]),
        .sr_read_data_i(sr_read_data_i[4096 +: 4096]),
        .sr_consume_o(sr_consume_o[64 +: 64]),
        .sr_write_valid_o(sr_write_valid_o[64 +: 64]),
        .sr_write_sel_o(sr_write_sel_o[96 +: 96]),
        .sr_write_data_o(sr_write_data_o[4096 +: 4096]),
        .fault_valid_o(fault_valid_o[1]),
        .transpose_input_invalid_o(transpose_input_invalid_o[4 +: 4]),
        .transpose_buffer_full_o(transpose_buffer_full_o[4 +: 4]),
        .permute_phase_fault_o(permute_phase_fault_o[1]),
        .permute_selector_fault_o(permute_selector_fault_o[1]),
        .permute_buffer_not_ready_o(permute_buffer_not_ready_o[1]),
        .busy_o(busy_o[1])
    );

endmodule
