`timescale 1ns/1ps

// System-level SXM slice verification for one 32x32 matrix and two matrices
// launched with a four-cycle start interval. Expected results are generated
// directly from Y[row][column] = X[column][row].
module tb_sxm_32x32;

    localparam integer TILE_ROWS = 4;
    localparam integer ACTIVE_STREAMS = 16;
    localparam integer SEGMENT_BITS = 64;
    localparam integer MATRIX_DIM = 32;
    localparam integer MATRIX_ELEMENTS = 1024;

    reg clk_i;
    reg rst_ni;
    reg transpose_cmd_valid_i;
    reg [95:0] transpose_cmd_i;
    reg permute_cmd_valid_i;
    reg [95:0] permute_cmd_i;
    wire [383:0] sr_read_req_o;
    reg [63:0] sr_read_valid_i;
    reg [4095:0] sr_read_data_i;
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

    reg [15:0] matrix_a [0:MATRIX_ELEMENTS-1];
    reg [15:0] matrix_b [0:MATRIX_ELEMENTS-1];
    reg [15:0] expected_a [0:MATRIX_ELEMENTS-1];
    reg [15:0] expected_b [0:MATRIX_ELEMENTS-1];
    reg [15:0] observed_a [0:MATRIX_ELEMENTS-1];
    reg [15:0] observed_b [0:MATRIX_ELEMENTS-1];
    integer seen_a [0:15];
    integer seen_b [0:15];

    integer errors;
    integer row;
    integer column;
    integer tile;
    integer stream;
    integer lane;
    integer plane;
    integer global_cycle;
    integer last_cycle;
    integer matrix_id;
    integer block_row;
    integer element_index;
    integer block_index;
    integer expected_active;
    integer trace_file;
    reg [15:0] element_value;
    reg [7:0] expected_byte;
    reg [7:0] actual_byte;

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

    // Return matrix ownership of a source-tile capture at a global wave.
    // 0 = matrix A, 1 = matrix B, -1 = inactive source tile.
    function integer capture_matrix;
        input integer wave;
        input integer source_tile;
        input integer two_matrices;
        begin
            if ((wave >= source_tile) &&
                (wave <= source_tile + 3)) begin
                capture_matrix = 0;
            end else if (two_matrices &&
                         (wave >= source_tile + 4) &&
                         (wave <= source_tile + 7)) begin
                capture_matrix = 1;
            end else begin
                capture_matrix = -1;
            end
        end
    endfunction

    function integer capture_block_row;
        input integer wave;
        input integer source_tile;
        input integer owner;
        begin
            if (owner == 0) begin
                capture_block_row = wave - source_tile;
            end else begin
                capture_block_row = wave - 4 - source_tile;
            end
        end
    endfunction

    task clear_drives;
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
            clear_drives();
            rst_ni = 1'b0;
            repeat (2) @(posedge clk_i);
            @(negedge clk_i);
            rst_ni = 1'b1;
        end
    endtask

    task initialize_scoreboard;
        begin
            for (element_index = 0; element_index < MATRIX_ELEMENTS;
                 element_index = element_index + 1) begin
                observed_a[element_index] = 16'b0;
                observed_b[element_index] = 16'b0;
            end
            for (block_index = 0; block_index < 16;
                 block_index = block_index + 1) begin
                seen_a[block_index] = 0;
                seen_b[block_index] = 0;
            end
        end
    endtask

    task drive_cycle;
        input integer wave;
        input integer two_matrices;
        begin
            clear_drives();

            // Four row-block launch beats per matrix. The registered control
            // column turns them into the seven diagonal capture waves.
            if ((wave >= 0) && (wave < 4)) begin
                transpose_cmd_valid_i = 1'b1;
            end else if (two_matrices && (wave >= 4) && (wave < 8)) begin
                transpose_cmd_valid_i = 1'b1;
            end
            transpose_cmd_i = make_command(2'd0, 1'b0, 5'd0,
                                           1'b1, 5'd0, 4'd8,
                                           4'd0, 3'd0, 8'd0);

            // A capture commits at the following edge. Permute observes and
            // releases that OLD entry in the next cycle.
            if (wave > 0) begin
                permute_cmd_valid_i = 1'b1;
                permute_cmd_i = make_command(2'd1, 1'b1, 5'd0,
                                             1'b0, 5'd16, 4'd0,
                                             4'd8, 3'd4,
                                             (wave - 1) & 8'h03);
            end

            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                matrix_id = capture_matrix(wave, tile, two_matrices);
                if (matrix_id >= 0) begin
                    block_row = capture_block_row(wave, tile, matrix_id);
                    sr_read_valid_i[tile*ACTIVE_STREAMS +:
                                    ACTIVE_STREAMS] = 16'hFFFF;
                    for (row = 0; row < 8; row = row + 1) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            element_index = (8*block_row + row)*MATRIX_DIM +
                                            8*tile + lane;
                            if (matrix_id == 0) begin
                                element_value = matrix_a[element_index];
                            end else begin
                                element_value = matrix_b[element_index];
                            end
                            for (plane = 0; plane < 2;
                                 plane = plane + 1) begin
                                sr_read_data_i[
                                    (tile*ACTIVE_STREAMS + 2*row + plane)*
                                    SEGMENT_BITS + lane*8 +: 8] =
                                    plane ? element_value[15:8] :
                                            element_value[7:0];
                            end
                        end
                    end
                end
            end
        end
    endtask

    task check_capture_and_faults;
        input integer wave;
        input integer two_matrices;
        begin
            if (fault_valid_o !== 1'b0 ||
                transpose_input_invalid_o !== 4'b0 ||
                transpose_buffer_full_o !== 4'b0 ||
                permute_phase_fault_o !== 1'b0 ||
                permute_selector_fault_o !== 1'b0 ||
                permute_buffer_not_ready_o !== 1'b0) begin
                $display("ERROR unexpected fault wave=%0d", wave);
                errors = errors + 1;
            end

            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                expected_active =
                    capture_matrix(wave, tile, two_matrices) >= 0;
                if (sr_consume_o[tile*ACTIVE_STREAMS +:
                                 ACTIVE_STREAMS] !==
                    (expected_active ? 16'hFFFF : 16'h0000)) begin
                    $display("ERROR consume wave=%0d tile=%0d", wave, tile);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task verify_previous_wave;
        input integer captured_wave;
        input integer two_matrices;
        reg [3:0] expected_destination_mask;
        begin
            expected_destination_mask = 4'b0;
            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                matrix_id = capture_matrix(captured_wave, tile,
                                           two_matrices);
                if (matrix_id >= 0) begin
                    block_row = capture_block_row(captured_wave, tile,
                                                  matrix_id);
                    expected_destination_mask[block_row] = 1'b1;
                end
            end

            for (block_row = 0; block_row < 4;
                 block_row = block_row + 1) begin
                if (sr_write_valid_o[
                        block_row*ACTIVE_STREAMS +: ACTIVE_STREAMS] !==
                    (expected_destination_mask[block_row] ?
                         16'hFFFF : 16'h0000)) begin
                    $display("ERROR output valid wave=%0d destination=%0d",
                             captured_wave, block_row);
                    errors = errors + 1;
                end
            end

            for (stream = 0; stream < ACTIVE_STREAMS;
                 stream = stream + 1) begin
                if (sr_write_sel_o[stream*6 +: 6] !==
                    (16 + stream)) begin
                    $display("ERROR write selector wave=%0d stream=%0d",
                             captured_wave, stream);
                    errors = errors + 1;
                end
            end

            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                matrix_id = capture_matrix(captured_wave, tile,
                                           two_matrices);
                if (matrix_id >= 0) begin
                    block_row = capture_block_row(captured_wave, tile,
                                                  matrix_id);
                    block_index = block_row*4 + tile;
                    if (matrix_id == 0) begin
                        seen_a[block_index] = seen_a[block_index] + 1;
                    end else begin
                        seen_b[block_index] = seen_b[block_index] + 1;
                    end

                    for (row = 0; row < 8; row = row + 1) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            element_index = (8*tile + row)*MATRIX_DIM +
                                            8*block_row + lane;
                            for (plane = 0; plane < 2;
                                 plane = plane + 1) begin
                                if (matrix_id == 0) begin
                                    element_value = expected_a[element_index];
                                end else begin
                                    element_value = expected_b[element_index];
                                end
                                expected_byte = plane ?
                                    element_value[15:8] : element_value[7:0];
                                actual_byte = sr_write_data_o[
                                    (block_row*ACTIVE_STREAMS +
                                     2*row + plane)*SEGMENT_BITS +
                                    lane*8 +: 8];
                                if (actual_byte !== expected_byte) begin
                                    $display("ERROR data matrix=%0d block=(%0d,%0d) row=%0d lane=%0d plane=%0d",
                                             matrix_id, block_row, tile,
                                             row, lane, plane);
                                    errors = errors + 1;
                                end
                                if (matrix_id == 0) begin
                                    if (plane == 0)
                                        observed_a[element_index][7:0] =
                                            actual_byte;
                                    else
                                        observed_a[element_index][15:8] =
                                            actual_byte;
                                end else begin
                                    if (plane == 0)
                                        observed_b[element_index][7:0] =
                                            actual_byte;
                                    else
                                        observed_b[element_index][15:8] =
                                            actual_byte;
                                end
                            end
                        end
                    end
                end
            end
        end
    endtask

    task check_matrix_completion;
        input integer two_matrices;
        begin
            for (block_index = 0; block_index < 16;
                 block_index = block_index + 1) begin
                if (seen_a[block_index] != 1) begin
                    $display("ERROR matrix A block count index=%0d count=%0d",
                             block_index, seen_a[block_index]);
                    errors = errors + 1;
                end
                if (two_matrices && (seen_b[block_index] != 1)) begin
                    $display("ERROR matrix B block count index=%0d count=%0d",
                             block_index, seen_b[block_index]);
                    errors = errors + 1;
                end
            end
            for (element_index = 0; element_index < MATRIX_ELEMENTS;
                 element_index = element_index + 1) begin
                if (observed_a[element_index] !== expected_a[element_index]) begin
                    $display("ERROR matrix A element index=%0d", element_index);
                    errors = errors + 1;
                end
                if (two_matrices &&
                    (observed_b[element_index] !== expected_b[element_index])) begin
                    $display("ERROR matrix B element index=%0d", element_index);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_wave4_commit;
        begin
            // At global wave4 the OLD tile0 entry (A.B30) was read before the
            // edge. The edge must atomically replace it with NEW B.B00.
            if (dut.result_buffer_ready[0] !== 1'b1) begin
                $display("ERROR wave4 tile0 replacement not ready");
                errors = errors + 1;
            end
            for (row = 0; row < 8; row = row + 1) begin
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    element_index = row*MATRIX_DIM + lane;
                    element_value = expected_b[element_index];
                    for (plane = 0; plane < 2; plane = plane + 1) begin
                        expected_byte = plane ? element_value[15:8] :
                                                element_value[7:0];
                        actual_byte = dut.result_buffer_data[
                            (2*row + plane)*SEGMENT_BITS + lane*8 +: 8];
                        if (actual_byte !== expected_byte) begin
                            $display("ERROR wave4 tile0 OLD/NEW ordering row=%0d lane=%0d plane=%0d",
                                     row, lane, plane);
                            errors = errors + 1;
                        end
                    end
                end
            end
            if (seen_b[0] != 0) begin
                $display("ERROR B.B00 became visible before next cycle");
                errors = errors + 1;
            end
        end
    endtask

    task run_case;
        input integer two_matrices;
        begin
            initialize_scoreboard();
            reset_dut();
            if (two_matrices) begin
                last_cycle = 11;
                trace_file = $fopen("sim/sxm_rtl_trace.txt", "w");
                if (trace_file == 0) begin
                    $display("ERROR cannot open RTL trace");
                    errors = errors + 1;
                end
            end else begin
                last_cycle = 7;
            end

            for (global_cycle = 0; global_cycle <= last_cycle;
                 global_cycle = global_cycle + 1) begin
                drive_cycle(global_cycle, two_matrices);
                #1;
                if (two_matrices && (trace_file != 0)) begin
                    $fdisplay(trace_file,
                              "CYCLE=%0d STAGE=%01h CONSUME=%016h READY=%01h AGE=%01h WRITE=%016h FAULT=%01h BUSY=%01h",
                              global_cycle,
                              dut.stage_cmd_valid,
                              sr_consume_o,
                              dut.result_buffer_ready,
                              dut.result_buffer_age_ok,
                              sr_write_valid_o,
                              fault_valid_o,
                              busy_o);
                end
                check_capture_and_faults(global_cycle, two_matrices);
                if (global_cycle > 0) begin
                    verify_previous_wave(global_cycle - 1, two_matrices);
                end
                @(posedge clk_i);
                #1;
                if (two_matrices && (global_cycle == 4)) begin
                    check_wave4_commit();
                end
                @(negedge clk_i);
            end
            clear_drives();
            check_matrix_completion(two_matrices);
            if (two_matrices && (trace_file != 0)) begin
                $fclose(trace_file);
                trace_file = 0;
            end
        end
    endtask

    initial begin
        errors = 0;
        trace_file = 0;
        rst_ni = 1'b0;
        clear_drives();

        // A follows the requested coordinate pattern. B sets a high marker
        // so overlap mixing is observable while retaining row/column identity.
        for (row = 0; row < MATRIX_DIM; row = row + 1) begin
            for (column = 0; column < MATRIX_DIM;
                 column = column + 1) begin
                matrix_a[row*MATRIX_DIM + column] =
                    (row << 8) | column;
                matrix_b[row*MATRIX_DIM + column] =
                    16'h8000 ^ ((row << 8) | column);
            end
        end
        for (row = 0; row < MATRIX_DIM; row = row + 1) begin
            for (column = 0; column < MATRIX_DIM;
                 column = column + 1) begin
                expected_a[row*MATRIX_DIM + column] =
                    matrix_a[column*MATRIX_DIM + row];
                expected_b[row*MATRIX_DIM + column] =
                    matrix_b[column*MATRIX_DIM + row];
            end
        end

        $display("RUN_TEST sxm_32x32_single_block");
        run_case(0);
        if (errors == 0) begin
            $display("SXM_32X32_SINGLE_BLOCK PASS");
        end

        $display("RUN_TEST sxm_32x32_continuous_ii4");
        run_case(1);
        if (errors == 0) begin
            $display("SXM_32X32_CONTINUOUS PASS");
        end
        $display("MATRIX_START_INTERVAL = 4");

        if (errors == 0) begin
            $display("================================");
            $display("SXM_32X32_REGRESSION TEST_PASS");
            $display("================================");
            $finish;
        end

        $display("SXM_32X32_REGRESSION TEST_FAIL errors=%0d", errors);
        $fatal(1);
    end

endmodule
