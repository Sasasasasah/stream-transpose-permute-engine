`timescale 1ns/1ps

module tb_sxm_full;

    reg clk_i;
    reg rst_ni;
    reg [1:0] transpose_cmd_valid_i;
    reg [191:0] transpose_cmd_i;
    reg [1:0] permute_cmd_valid_i;
    reg [191:0] permute_cmd_i;
    wire [767:0] sr_read_req_o;
    reg [127:0] sr_read_valid_i;
    reg [8191:0] sr_read_data_i;
    wire [127:0] sr_consume_o;
    wire [127:0] sr_write_valid_o;
    wire [191:0] sr_write_sel_o;
    wire [8191:0] sr_write_data_o;
    wire [1:0] fault_valid_o;
    wire [7:0] transpose_input_invalid_o;
    wire [7:0] transpose_buffer_full_o;
    wire [1:0] permute_phase_fault_o;
    wire [1:0] permute_selector_fault_o;
    wire [1:0] permute_buffer_not_ready_o;
    wire [1:0] busy_o;

    integer errors;
    integer stream;
    reg [95:0] west_command;
    reg [95:0] east_command;

    sxm_full dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .transpose_cmd_valid_i(transpose_cmd_valid_i),
        .transpose_cmd_i(transpose_cmd_i),
        .permute_cmd_valid_i(permute_cmd_valid_i),
        .permute_cmd_i(permute_cmd_i),
        .sr_read_req_o(sr_read_req_o),
        .sr_read_valid_i(sr_read_valid_i),
        .sr_read_data_i(sr_read_data_i),
        .sr_consume_o(sr_consume_o),
        .sr_write_valid_o(sr_write_valid_o),
        .sr_write_sel_o(sr_write_sel_o),
        .sr_write_data_o(sr_write_data_o),
        .fault_valid_o(fault_valid_o),
        .transpose_input_invalid_o(transpose_input_invalid_o),
        .transpose_buffer_full_o(transpose_buffer_full_o),
        .permute_phase_fault_o(permute_phase_fault_o),
        .permute_selector_fault_o(permute_selector_fault_o),
        .permute_buffer_not_ready_o(permute_buffer_not_ready_o),
        .busy_o(busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [95:0] make_command;
        input [1:0] opcode;
        input src_direction;
        input [4:0] src_base;
        input dst_direction;
        input [4:0] dst_base;
        input [3:0] input_row;
        input [3:0] output_row;
        input [2:0] output_tile;
        input [7:0] phase_id;
        reg [95:0] value;
        begin
            value = 96'b0;
            value[1:0] = opcode;
            value[2] = src_direction;
            value[7:3] = src_base;
            value[8] = dst_direction;
            value[13:9] = dst_base;
            value[17:14] = input_row;
            value[21:18] = output_row;
            value[24:22] = output_tile;
            value[32:25] = phase_id;
            make_command = value;
        end
    endfunction

    task clear_inputs;
        begin
            transpose_cmd_valid_i = 2'b00;
            transpose_cmd_i = 192'b0;
            permute_cmd_valid_i = 2'b00;
            permute_cmd_i = 192'b0;
            sr_read_valid_i = 128'b0;
            sr_read_data_i = 8192'b0;
        end
    endtask

    task reset_dut;
        begin
            clear_inputs();
            rst_ni = 1'b0;
            repeat (2) @(posedge clk_i);
            @(negedge clk_i);
            rst_ni = 1'b1;
        end
    endtask

    task fill_tile_uniform;
        input integer hemisphere;
        input integer tile;
        input [7:0] value;
        begin
            sr_read_data_i[
                hemisphere*4096 + tile*1024 +: 1024] = {128{value}};
        end
    endtask

    task check_read_selectors;
        input integer hemisphere;
        input integer tile;
        input direction;
        input integer base;
        begin
            for (stream = 0; stream < 16; stream = stream + 1) begin
                if (sr_read_req_o[
                        hemisphere*384 + (tile*16 + stream)*6 +: 6] !==
                    ((direction ? 32 : 0) + base + stream)) begin
                    $display("ERROR read selector hemi=%0d tile=%0d stream=%0d",
                             hemisphere, tile, stream);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_write_selectors;
        input integer hemisphere;
        input direction;
        input integer base;
        begin
            for (stream = 0; stream < 16; stream = stream + 1) begin
                if (sr_write_sel_o[
                        hemisphere*96 + stream*6 +: 6] !==
                    ((direction ? 32 : 0) + base + stream)) begin
                    $display("ERROR write selector hemi=%0d stream=%0d",
                             hemisphere, stream);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b0;
        clear_inputs();

        $display("RUN_TEST reset_idle");
        reset_dut();
        #1;
        if (busy_o !== 2'b00 || fault_valid_o !== 2'b00 ||
            sr_consume_o !== 128'b0 || sr_write_valid_o !== 128'b0) begin
            $display("ERROR reset idle");
            errors = errors + 1;
        end

        $display("RUN_TEST west_hemisphere_only");
        clear_inputs();
        west_command = make_command(2'd0, 1'b0, 5'd0,
                                    1'b1, 5'd8, 4'd8,
                                    4'd0, 3'd0, 8'd0);
        transpose_cmd_valid_i[0] = 1'b1;
        transpose_cmd_i[0 +: 96] = west_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 0, 8'hA0);
        #1;
        check_read_selectors(0, 0, 1'b0, 0);
        if (sr_consume_o[0 +: 64] !== 64'h0000_0000_0000_FFFF ||
            sr_consume_o[64 +: 64] !== 64'b0 ||
            busy_o !== 2'b01 || fault_valid_o !== 2'b00) begin
            $display("ERROR west-only isolation");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.u_west_slice.result_buffer_data[0 +: 1024] !==
                {128{8'hA0}} ||
            dut.u_east_slice.result_buffer_ready !== 4'b0000) begin
            $display("ERROR west-only buffer ownership");
            errors = errors + 1;
        end

        $display("RUN_TEST east_hemisphere_only");
        reset_dut();
        east_command = make_command(2'd0, 1'b1, 5'd4,
                                    1'b0, 5'd16, 4'd8,
                                    4'd0, 3'd0, 8'd0);
        transpose_cmd_valid_i[1] = 1'b1;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[64 +: 16] = 16'hFFFF;
        fill_tile_uniform(1, 0, 8'hB1);
        #1;
        check_read_selectors(1, 0, 1'b1, 4);
        if (sr_consume_o[64 +: 64] !== 64'h0000_0000_0000_FFFF ||
            sr_consume_o[0 +: 64] !== 64'b0 ||
            busy_o !== 2'b10 || fault_valid_o !== 2'b00) begin
            $display("ERROR east-only isolation");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.u_east_slice.result_buffer_data[0 +: 1024] !==
                {128{8'hB1}} ||
            dut.u_west_slice.result_buffer_ready !== 4'b0000) begin
            $display("ERROR east-only buffer ownership");
            errors = errors + 1;
        end

        $display("RUN_TEST simultaneous_independent_commands_and_data");
        reset_dut();
        west_command = make_command(2'd0, 1'b0, 5'd0,
                                    1'b1, 5'd8, 4'd8,
                                    4'd0, 3'd0, 8'd0);
        east_command = make_command(2'd0, 1'b1, 5'd4,
                                    1'b0, 5'd16, 4'd8,
                                    4'd0, 3'd0, 8'd0);
        transpose_cmd_valid_i = 2'b11;
        transpose_cmd_i[0 +: 96] = west_command;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        sr_read_valid_i[64 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 0, 8'h3C);
        fill_tile_uniform(1, 0, 8'hD7);
        #1;
        check_read_selectors(0, 0, 1'b0, 0);
        check_read_selectors(1, 0, 1'b1, 4);
        if (sr_consume_o !==
            {48'b0,16'hFFFF,48'b0,16'hFFFF}) begin
            $display("ERROR simultaneous consume packing");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.u_west_slice.result_buffer_data[0 +: 1024] !==
                {128{8'h3C}} ||
            dut.u_east_slice.result_buffer_data[0 +: 1024] !==
                {128{8'hD7}}) begin
            $display("ERROR cross-hemisphere data isolation");
            errors = errors + 1;
        end

        $display("RUN_TEST independent_permute_output");
        @(negedge clk_i);
        clear_inputs();
        // The two Transpose commands are now at tile1; provide independent
        // legal responses while Permute reads the OLD tile0 buffers.
        sr_read_valid_i[16 +: 16] = 16'hFFFF;
        sr_read_valid_i[64+16 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 1, 8'h4D);
        fill_tile_uniform(1, 1, 8'hE8);
        permute_cmd_valid_i = 2'b11;
        permute_cmd_i[0 +: 96] =
            make_command(2'd1, 1'b1, 5'd8,
                         1'b0, 5'd16, 4'd0,
                         4'd8, 3'd0, 8'd0);
        permute_cmd_i[96 +: 96] =
            make_command(2'd1, 1'b0, 5'd16,
                         1'b1, 5'd4, 4'd0,
                         4'd8, 3'd1, 8'd1);
        #1;
        check_write_selectors(0, 1'b0, 16);
        check_write_selectors(1, 1'b1, 4);
        if (sr_write_valid_o[0 +: 64] !==
                64'h0000_0000_0000_FFFF ||
            sr_write_valid_o[64 +: 64] !==
                64'h0000_0000_FFFF_0000 ||
            sr_write_data_o[0 +: 1024] !== {128{8'h3C}} ||
            sr_write_data_o[4096+1024 +: 1024] !== {128{8'hD7}} ||
            fault_valid_o !== 2'b00) begin
            $display("ERROR independent Permute output");
            errors = errors + 1;
        end

        $display("RUN_TEST busy_independence");
        reset_dut();
        transpose_cmd_valid_i[0] = 1'b1;
        transpose_cmd_i[0 +: 96] = west_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 0, 8'h51);
        @(posedge clk_i);
        @(negedge clk_i);
        clear_inputs();
        #1;
        if (busy_o !== 2'b01) begin
            $display("ERROR west busy independence");
            errors = errors + 1;
        end
        reset_dut();
        transpose_cmd_valid_i[1] = 1'b1;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[64 +: 16] = 16'hFFFF;
        fill_tile_uniform(1, 0, 8'h62);
        @(posedge clk_i);
        @(negedge clk_i);
        clear_inputs();
        #1;
        if (busy_o !== 2'b10) begin
            $display("ERROR east busy independence");
            errors = errors + 1;
        end

        $display("RUN_TEST fault_independence");
        reset_dut();
        transpose_cmd_valid_i = 2'b11;
        transpose_cmd_i[0 +: 96] = west_command;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFE;
        sr_read_valid_i[64 +: 16] = 16'hFFFF;
        fill_tile_uniform(1, 0, 8'h73);
        #1;
        if (fault_valid_o !== 2'b01 ||
            sr_consume_o[64 +: 16] !== 16'hFFFF) begin
            $display("ERROR west fault independence");
            errors = errors + 1;
        end
        reset_dut();
        transpose_cmd_valid_i = 2'b11;
        transpose_cmd_i[0 +: 96] = west_command;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        sr_read_valid_i[64 +: 16] = 16'hFFFE;
        fill_tile_uniform(0, 0, 8'h84);
        #1;
        if (fault_valid_o !== 2'b10 ||
            sr_consume_o[0 +: 16] !== 16'hFFFF) begin
            $display("ERROR east fault independence");
            errors = errors + 1;
        end

        $display("RUN_TEST concurrent_cross_hemisphere_transpose_permute");
        reset_dut();
        transpose_cmd_valid_i[1] = 1'b1;
        transpose_cmd_i[96 +: 96] = east_command;
        sr_read_valid_i[64 +: 16] = 16'hFFFF;
        fill_tile_uniform(1, 0, 8'h95);
        @(posedge clk_i);
        @(negedge clk_i);
        clear_inputs();
        transpose_cmd_valid_i[0] = 1'b1;
        transpose_cmd_i[0 +: 96] = west_command;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        sr_read_valid_i[64+16 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 0, 8'hA6);
        fill_tile_uniform(1, 1, 8'hB7);
        permute_cmd_valid_i[1] = 1'b1;
        permute_cmd_i[96 +: 96] =
            make_command(2'd1, 1'b0, 5'd16,
                         1'b1, 5'd4, 4'd0,
                         4'd8, 3'd0, 8'd0);
        #1;
        if (sr_consume_o[0 +: 16] !== 16'hFFFF ||
            sr_write_valid_o[64 +: 16] !== 16'hFFFF ||
            sr_write_data_o[4096 +: 1024] !== {128{8'h95}} ||
            fault_valid_o !== 2'b00) begin
            $display("ERROR concurrent cross-hemisphere operation");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("RTL_SXM_FULL_REGRESSION PASS");
            $finish;
        end
        $display("RTL_SXM_FULL_REGRESSION FAIL errors=%0d", errors);
        $fatal(1);
    end

endmodule
