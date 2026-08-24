`timescale 1ns/1ps

module tb_sxm_slice;

    reg clk_i;
    reg rst_ni;
    reg transpose_cmd_valid_i;
    reg [95:0] transpose_cmd_i;
    reg permute_cmd_valid_i;
    reg [95:0] permute_cmd_i;
    reg [63:0] sr_read_valid_i;
    reg [4095:0] sr_read_data_i;

    wire [383:0] sr_read_req_o;
    wire [63:0] sr_consume_o;
    wire [63:0] sr_write_valid_o;
    wire [95:0] sr_write_sel_o;
    wire [4095:0] sr_write_data_o;
    wire fault_valid_o;
    wire [3:0] transpose_input_invalid_o;
    wire [3:0] transpose_buffer_full_o;
    wire permute_phase_fault_o;
    wire permute_selector_fault_o;
    wire permute_buffer_not_ready_o;
    wire busy_o;

    integer errors;
    integer tile;
    integer stream;
    integer byte_index;
    integer expected_index;
    integer legality_errors_before;

    reg [95:0] command_a;
    reg [95:0] command_b;
    reg [95:0] command_c;
    reg [95:0] command_d;
    reg [95:0] command_new;

    sxm_slice dut (
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
            transpose_cmd_valid_i = 1'b0;
            transpose_cmd_i = 96'b0;
            permute_cmd_valid_i = 1'b0;
            permute_cmd_i = 96'b0;
            sr_read_valid_i = 64'b0;
            sr_read_data_i = 4096'b0;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk_i);
            rst_ni = 1'b0;
            clear_inputs();
            repeat (2) begin
                @(posedge clk_i);
                #1;
            end
            if (busy_o !== 1'b0 || sr_consume_o !== 64'b0 ||
                sr_write_valid_o !== 64'b0 || fault_valid_o !== 1'b0) begin
                $display("ERROR reset idle outputs");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            #1;
        end
    endtask

    task fill_tile_uniform;
        input integer tile_index;
        input [7:0] value;
        begin
            for (byte_index = 0; byte_index < 128;
                 byte_index = byte_index + 1) begin
                sr_read_data_i[
                    tile_index*1024 + byte_index*8 +: 8] = value;
            end
        end
    endtask

    task check_read_selectors;
        input integer tile_index;
        input expected_direction;
        input integer expected_base;
        begin
            for (stream = 0; stream < 16; stream = stream + 1) begin
                expected_index = expected_base + stream;
                if (sr_read_req_o[(tile_index*16+stream)*6 +: 6] !==
                    {expected_direction, expected_index[4:0]}) begin
                    $display("ERROR read selector tile=%0d stream=%0d",
                             tile_index, stream);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_write_selectors;
        input expected_direction;
        input integer expected_base;
        begin
            for (stream = 0; stream < 16; stream = stream + 1) begin
                expected_index = expected_base + stream;
                if (sr_write_sel_o[stream*6 +: 6] !==
                    {expected_direction, expected_index[4:0]}) begin
                    $display("ERROR write selector stream=%0d", stream);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task drive_command_and_advance;
        input [95:0] command_value;
        input wait_negedge;
        begin
            if (wait_negedge)
                @(negedge clk_i);
            transpose_cmd_valid_i = 1'b1;
            transpose_cmd_i = command_value;
            permute_cmd_valid_i = 1'b0;
            sr_read_valid_i = 64'b0;
            sr_read_data_i = 4096'b0;
            @(posedge clk_i);
            #1;
        end
    endtask

    task flush_transpose_pipeline;
        integer flush_cycle;
        begin
            for (flush_cycle = 0; flush_cycle < 3;
                 flush_cycle = flush_cycle + 1) begin
                @(negedge clk_i);
                clear_inputs();
                @(posedge clk_i);
                #1;
            end
        end
    endtask

    task seed_four_buffers;
        begin
            command_a = make_command(2'd0, 1'b0, 5'd16,
                                     1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
            command_b = make_command(2'd0, 1'b0, 5'd8,
                                     1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
            command_c = make_command(2'd0, 1'b1, 5'd4,
                                     1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
            command_d = make_command(2'd0, 1'b0, 5'd0,
                                     1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);

            drive_command_and_advance(command_a, 1'b0);
            drive_command_and_advance(command_b, 1'b1);
            drive_command_and_advance(command_c, 1'b1);

            @(negedge clk_i);
            transpose_cmd_valid_i = 1'b1;
            transpose_cmd_i = command_d;
            permute_cmd_valid_i = 1'b0;
            sr_read_valid_i = 64'hFFFF_FFFF_FFFF_FFFF;
            sr_read_data_i = 4096'b0;
            fill_tile_uniform(0, 8'hA0);
            fill_tile_uniform(1, 8'hB1);
            fill_tile_uniform(2, 8'hC2);
            fill_tile_uniform(3, 8'hD3);
            #1;
            if (sr_consume_o !== 64'hFFFF_FFFF_FFFF_FFFF) begin
                $display("ERROR four-stage consume");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;
            if (dut.result_buffer_ready !== 4'b1111) begin
                $display("ERROR four buffers not ready");
                errors = errors + 1;
            end
            if (dut.result_buffer_data[0*1024 +: 1024] !== {128{8'hA0}} ||
                dut.result_buffer_data[1*1024 +: 1024] !== {128{8'hB1}} ||
                dut.result_buffer_data[2*1024 +: 1024] !== {128{8'hC2}} ||
                dut.result_buffer_data[3*1024 +: 1024] !== {128{8'hD3}} ||
                dut.result_buffer_dst_meta !== {4{6'h28}}) begin
                $display("ERROR mixed tile data or metadata capture");
                errors = errors + 1;
            end
        end
    endtask

    task check_direction_path;
        input src_direction;
        input dst_direction;
        input [7:0] pattern;
        begin
            reset_dut();
            transpose_cmd_valid_i = 1'b1;
            transpose_cmd_i = make_command(2'd0, src_direction, 5'd0,
                                           dst_direction, 5'd8, 4'd8,
                                           4'd0, 3'd0, 8'd0);
            sr_read_valid_i[0 +: 16] = 16'hFFFF;
            fill_tile_uniform(0, pattern);
            #1;
            check_read_selectors(0, src_direction, 0);
            @(posedge clk_i);
            #1;
            if (dut.result_buffer_dst_meta[0 +: 6] !==
                {dst_direction, 5'd8}) begin
                $display("ERROR direction metadata src=%0d dst=%0d",
                         src_direction, dst_direction);
                errors = errors + 1;
            end

            @(negedge clk_i);
            clear_inputs();
            // The Transpose command has advanced to tile1. Keep that stage
            // legal while Permute consumes the OLD tile0 buffer.
            sr_read_valid_i[16 +: 16] = 16'hFFFF;
            permute_cmd_valid_i = 1'b1;
            permute_cmd_i = make_command(2'd1, dst_direction, 5'd8,
                                         dst_direction, 5'd16, 4'd0,
                                         4'd8, 3'd0, 8'd0);
            #1;
            check_write_selectors(dst_direction, 16);
            if (sr_write_valid_o !==
                    64'h0000_0000_0000_FFFF ||
                sr_write_data_o[0 +: 1024] !== {128{pattern}} ||
                fault_valid_o !== 1'b0) begin
                $display("ERROR direction path src=%0d dst=%0d",
                         src_direction, dst_direction);
                errors = errors + 1;
            end
        end
    endtask

    task check_invalid_transpose_command;
        input [95:0] invalid_command;
        begin
            reset_dut();
            transpose_cmd_valid_i = 1'b1;
            transpose_cmd_i = invalid_command;
            sr_read_valid_i[0 +: 16] = 16'hFFFF;
            fill_tile_uniform(0, 8'hEE);
            #1;
            if (sr_read_req_o !== 384'b0 || sr_consume_o !== 64'b0 ||
                fault_valid_o !== 1'b1 || busy_o !== 1'b0) begin
                $display("ERROR invalid Transpose did not fail closed");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;
            if (dut.result_buffer_ready !== 4'b0000 ||
                dut.stage_cmd_valid !== 4'b0000) begin
                $display("ERROR invalid Transpose entered state");
                errors = errors + 1;
            end
        end
    endtask

    task check_invalid_permute_command;
        input [95:0] invalid_command;
        begin
            reset_dut();
            transpose_cmd_valid_i = 1'b1;
            transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                           1'b0, 5'd8, 4'd8,
                                           4'd0, 3'd0, 8'd0);
            sr_read_valid_i[0 +: 16] = 16'hFFFF;
            fill_tile_uniform(0, 8'hCD);
            @(posedge clk_i);
            @(negedge clk_i);
            clear_inputs();
            sr_read_valid_i[16 +: 16] = 16'hFFFF;
            permute_cmd_valid_i = 1'b1;
            permute_cmd_i = invalid_command;
            #1;
            if (sr_write_valid_o !== 64'b0 || sr_write_sel_o !== 96'b0 ||
                fault_valid_o !== 1'b1) begin
                $display("ERROR invalid Permute did not fail closed");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;
            if (dut.result_buffer_ready[0] !== 1'b1) begin
                $display("ERROR invalid Permute released source buffer");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b0;
        clear_inputs();

        $display("RUN_TEST reset_idle");
        reset_dut();

        $display("RUN_TEST independent_per_tile_read_selector");
        command_a = make_command(2'd0, 1'b0, 5'd16,
                                 1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
        command_b = make_command(2'd0, 1'b0, 5'd8,
                                 1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
        command_c = make_command(2'd0, 1'b1, 5'd4,
                                 1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
        command_d = make_command(2'd0, 1'b0, 5'd0,
                                 1'b1, 5'd8, 4'd8, 4'd0, 3'd0, 8'd0);
        drive_command_and_advance(command_a, 1'b0);
        drive_command_and_advance(command_b, 1'b1);
        drive_command_and_advance(command_c, 1'b1);
        @(negedge clk_i);
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = command_d;
        #1;
        check_read_selectors(0, 1'b0, 0);
        check_read_selectors(1, 1'b1, 4);
        check_read_selectors(2, 1'b0, 8);
        check_read_selectors(3, 1'b0, 16);
        if (busy_o !== 1'b1) begin
            $display("ERROR control-pipeline busy missing");
            errors = errors + 1;
        end

        $display("RUN_TEST current_sr_to_transpose_buffer_different_src_dst");
        reset_dut();
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                       1'b1, 5'd8, 4'd8,
                                       4'd0, 3'd0, 8'd0);
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 8'h55);
        #1;
        check_read_selectors(0, 1'b0, 0);
        if (sr_consume_o[0 +: 16] !== 16'hFFFF) begin
            $display("ERROR tile0 consume");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.result_buffer_ready[0] !== 1'b1 ||
            dut.result_buffer_data[0 +: 1024] !== {128{8'h55}} ||
            dut.result_buffer_dst_meta[0 +: 6] !== 6'h28) begin
            $display("ERROR tile0 buffer data or West-base8 metadata");
            errors = errors + 1;
        end

        $display("RUN_TEST direction_contract_EE_WW_EW_WE");
        check_direction_path(1'b0, 1'b0, 8'h11);
        check_direction_path(1'b1, 1'b1, 8'h22);
        check_direction_path(1'b0, 1'b1, 8'h33);
        check_direction_path(1'b1, 1'b0, 8'h44);

        $display("RUN_TEST four_stage_mixed_command_capture");
        reset_dut();
        seed_four_buffers();
        if (busy_o !== 1'b1) begin
            $display("ERROR ready-buffer busy missing");
            errors = errors + 1;
        end

        $display("RUN_TEST result_buffer_permute_sr_write_consistent_metadata");
        flush_transpose_pipeline();
        @(negedge clk_i);
        clear_inputs();
        permute_cmd_valid_i = 1'b1;
        permute_cmd_i = make_command(2'd1, 1'b1, 5'd8,
                                     1'b0, 5'd16, 4'd8,
                                     4'd8, 3'd4, 8'd1);
        #1;
        if (sr_write_valid_o !== 64'hFFFF_FFFF_FFFF_FFFF ||
            permute_phase_fault_o !== 1'b0 ||
            permute_selector_fault_o !== 1'b0 ||
            permute_buffer_not_ready_o !== 1'b0) begin
            $display("ERROR legal Permute control");
            errors = errors + 1;
        end
        check_write_selectors(1'b0, 16);
        if (dut.result_buffer_dst_meta !== {4{6'h28}}) begin
            $display("ERROR legal metadata precondition");
            errors = errors + 1;
        end
        if (sr_write_data_o[0*1024 +: 1024] !== {128{8'hB1}} ||
            sr_write_data_o[1*1024 +: 1024] !== {128{8'hA0}} ||
            sr_write_data_o[2*1024 +: 1024] !== {128{8'hD3}} ||
            sr_write_data_o[3*1024 +: 1024] !== {128{8'hC2}}) begin
            $display("ERROR phase1 buffer-to-SR routing");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.result_buffer_ready !== 4'b0000) begin
            $display("ERROR Permute did not release all buffers");
            errors = errors + 1;
        end

        $display("RUN_TEST simultaneous_permute_release_transpose_write");
        reset_dut();
        seed_four_buffers();
        flush_transpose_pipeline();
        @(negedge clk_i);
        clear_inputs();
        command_new = make_command(2'd0, 1'b0, 5'd0,
                                   1'b1, 5'd8, 4'd8,
                                   4'd0, 3'd0, 8'd0);
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = command_new;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 8'h5A);
        permute_cmd_valid_i = 1'b1;
        permute_cmd_i = make_command(2'd1, 1'b1, 5'd8,
                                     1'b0, 5'd16, 4'd8,
                                     4'd8, 3'd4, 8'd0);
        #1;
        if (sr_write_data_o[0*1024 +: 1024] !== {128{8'hA0}} ||
            sr_write_data_o[1*1024 +: 1024] !== {128{8'hD3}} ||
            sr_write_data_o[2*1024 +: 1024] !== {128{8'hC2}} ||
            sr_write_data_o[3*1024 +: 1024] !== {128{8'hB1}} ||
            sr_consume_o[0 +: 16] !== 16'hFFFF ||
            transpose_buffer_full_o[0] !== 1'b0) begin
            $display("ERROR simultaneous cycle OLD output or NEW capture");
            errors = errors + 1;
        end
        @(posedge clk_i);
        #1;
        if (dut.result_buffer_ready !== 4'b0001 ||
            dut.result_buffer_data[0 +: 1024] !== {128{8'h5A}} ||
            dut.result_buffer_dst_meta[0 +: 6] !== 6'h28) begin
            $display("ERROR read-old write-new commit");
            errors = errors + 1;
        end

        $display("RUN_TEST local_fault_aggregation");
        reset_dut();
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                       1'b0, 5'd0, 4'd8,
                                       4'd0, 3'd0, 8'd0);
        sr_read_valid_i[0 +: 16] = 16'hFFFE;
        #1;
        if (transpose_input_invalid_o[0] !== 1'b1 ||
            fault_valid_o !== 1'b1) begin
            $display("ERROR transpose invalid-input aggregation");
            errors = errors + 1;
        end

        reset_dut();
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                       1'b0, 5'd0, 4'd8,
                                       4'd0, 3'd0, 8'd0);
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        fill_tile_uniform(0, 8'h66);
        @(posedge clk_i);
        #1;
        @(negedge clk_i);
        transpose_cmd_valid_i = 1'b1;
        sr_read_valid_i = 64'b0;
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        #1;
        if (transpose_buffer_full_o[0] !== 1'b1 ||
            fault_valid_o !== 1'b1) begin
            $display("ERROR transpose buffer-full aggregation");
            errors = errors + 1;
        end

        reset_dut();
        permute_cmd_valid_i = 1'b1;
        permute_cmd_i = make_command(2'd1, 1'b0, 5'd0,
                                     1'b0, 5'd0, 4'd8,
                                     4'd8, 3'd0, 8'd0);
        #1;
        if (permute_buffer_not_ready_o !== 1'b1 ||
            fault_valid_o !== 1'b1) begin
            $display("ERROR Permute not-ready aggregation");
            errors = errors + 1;
        end
        permute_cmd_i[32:25] = 8'd4;
        #1;
        if (permute_phase_fault_o !== 1'b1 || fault_valid_o !== 1'b1) begin
            $display("ERROR Permute phase aggregation");
            errors = errors + 1;
        end
        permute_cmd_i[32:25] = 8'd0;
        permute_cmd_i[21:18] = 4'd9;
        #1;
        if (permute_selector_fault_o !== 1'b1 ||
            fault_valid_o !== 1'b1) begin
            $display("ERROR Permute selector aggregation");
            errors = errors + 1;
        end


        $display("RUN_TEST command_legality_fail_closed_no_stall");
        legality_errors_before = errors;
        check_invalid_transpose_command(
            make_command(2'd0, 1'b0, 5'd17, 1'b0, 5'd0,
                         4'd8, 4'd0, 3'd0, 8'd0));
        check_invalid_transpose_command(
            make_command(2'd0, 1'b0, 5'd0, 1'b0, 5'd17,
                         4'd8, 4'd0, 3'd0, 8'd0));
        check_invalid_transpose_command(
            make_command(2'd1, 1'b0, 5'd0, 1'b0, 5'd0,
                         4'd8, 4'd0, 3'd0, 8'd0));
        check_invalid_transpose_command(
            make_command(2'd0, 1'b0, 5'd0, 1'b0, 5'd0,
                         4'd7, 4'd0, 3'd0, 8'd0));
        command_new = make_command(2'd0, 1'b0, 5'd0, 1'b0, 5'd0,
                                   4'd8, 4'd0, 3'd0, 8'd0);
        command_new[33] = 1'b1;
        check_invalid_transpose_command(command_new);

        check_invalid_permute_command(
            make_command(2'd1, 1'b0, 5'd0, 1'b0, 5'd17,
                         4'd0, 4'd8, 3'd0, 8'd0));
        check_invalid_permute_command(
            make_command(2'd0, 1'b0, 5'd0, 1'b0, 5'd16,
                         4'd0, 4'd8, 3'd0, 8'd0));
        check_invalid_permute_command(
            make_command(2'd1, 1'b0, 5'd17, 1'b0, 5'd16,
                         4'd0, 4'd8, 3'd0, 8'd0));
        command_new = make_command(2'd1, 1'b0, 5'd0, 1'b0, 5'd16,
                                   4'd0, 4'd8, 3'd0, 8'd0);
        command_new[95] = 1'b1;
        check_invalid_permute_command(command_new);

        // A command fault is a pulse. A legal issue in the next cycle must
        // proceed immediately without retry/recovery state.
        reset_dut();
        transpose_cmd_valid_i = 1'b1;
        transpose_cmd_i = make_command(2'd0, 1'b0, 5'd17,
                                       1'b0, 5'd0, 4'd8,
                                       4'd0, 3'd0, 8'd0);
        #1;
        @(posedge clk_i);
        @(negedge clk_i);
        transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                       1'b0, 5'd8, 4'd8,
                                       4'd0, 3'd0, 8'd0);
        sr_read_valid_i[0 +: 16] = 16'hFFFF;
        #1;
        if (fault_valid_o !== 1'b0 ||
            sr_consume_o[0 +: 16] !== 16'hFFFF) begin
            $display("ERROR legal command stalled after command fault");
            errors = errors + 1;
        end
        if (errors == legality_errors_before) begin
            $display("RTL_SXM_COMMAND_LEGALITY PASS");
        end

        $display("RUN_TEST busy_returns_idle_after_reset");
        reset_dut();
        if (busy_o !== 1'b0) begin
            $display("ERROR final idle busy");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("RTL_SXM_SLICE_REGRESSION PASS");
            $finish;
        end

        $display("RTL_SXM_SLICE_REGRESSION FAIL errors=%0d", errors);
        $fatal(1);
    end

endmodule
