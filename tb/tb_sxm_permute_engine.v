`timescale 1ns/1ps

module tb_sxm_permute_engine;

    localparam integer TILE_ROWS = 4;
    localparam integer ACTIVE_STREAMS = 16;
    localparam integer SEGMENT_BITS = 64;
    localparam integer BUFFER_BITS = 1024;

    reg cmd_valid_i;
    reg [7:0] phase_id_i;
    reg [3:0] output_row_i;
    reg [2:0] output_tile_i;
    reg [3:0] buffer_ready_i;
    reg [3:0] buffer_age_ok_i;
    reg [4095:0] buffer_data_i;
    reg [23:0] buffer_dst_meta_i;

    wire [7:0] source_tile_sel_o;
    wire [63:0] dst_valid_o;
    wire [4095:0] dst_data_o;
    wire [3:0] buffer_release_o;
    wire fault_phase_o;
    wire fault_selector_o;
    wire fault_buffer_not_ready_o;

    integer errors;
    integer tile;
    integer stream;
    integer lane;
    integer phase;
    integer row;
    integer source;
    reg expected_valid;
    reg [7:0] expected_byte;

    sxm_permute_engine dut (
        .cmd_valid_i(cmd_valid_i),
        .phase_id_i(phase_id_i),
        .output_row_i(output_row_i),
        .output_tile_i(output_tile_i),
        .buffer_ready_i(buffer_ready_i),
        .buffer_age_ok_i(buffer_age_ok_i),
        .buffer_data_i(buffer_data_i),
        .buffer_dst_meta_i(buffer_dst_meta_i),
        .source_tile_sel_o(source_tile_sel_o),
        .dst_valid_o(dst_valid_o),
        .dst_data_o(dst_data_o),
        .buffer_release_o(buffer_release_o),
        .fault_phase_o(fault_phase_o),
        .fault_selector_o(fault_selector_o),
        .fault_buffer_not_ready_o(fault_buffer_not_ready_o)
    );

    function integer expected_source_tile;
        input integer phase_value;
        input integer destination_value;
        begin
            case (phase_value)
                0: begin
                    case (destination_value)
                        0: expected_source_tile = 0;
                        1: expected_source_tile = 3;
                        2: expected_source_tile = 2;
                        default: expected_source_tile = 1;
                    endcase
                end
                1: begin
                    case (destination_value)
                        0: expected_source_tile = 1;
                        1: expected_source_tile = 0;
                        2: expected_source_tile = 3;
                        default: expected_source_tile = 2;
                    endcase
                end
                2: begin
                    case (destination_value)
                        0: expected_source_tile = 2;
                        1: expected_source_tile = 1;
                        2: expected_source_tile = 0;
                        default: expected_source_tile = 3;
                    endcase
                end
                default: begin
                    case (destination_value)
                        0: expected_source_tile = 3;
                        1: expected_source_tile = 2;
                        2: expected_source_tile = 1;
                        default: expected_source_tile = 0;
                    endcase
                end
            endcase
        end
    endfunction

    task load_unique_buffers;
        begin
            buffer_data_i = 4096'b0;
            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                for (stream = 0; stream < ACTIVE_STREAMS;
                     stream = stream + 1) begin
                    for (lane = 0; lane < 8; lane = lane + 1) begin
                        buffer_data_i[
                            tile*BUFFER_BITS + stream*SEGMENT_BITS +
                            lane*8 +: 8] =
                            tile*8'h43 + stream*8'h0B + lane*8'h1D;
                    end
                end
            end
        end
    endtask

    task set_legal_command;
        begin
            cmd_valid_i = 1'b1;
            phase_id_i = 8'd0;
            output_row_i = 4'd8;
            output_tile_i = 3'd4;
            buffer_ready_i = 4'b1111;
            buffer_age_ok_i = 4'b1111;
            buffer_dst_meta_i = {6'h33, 6'h22, 6'h11, 6'h00};
            load_unique_buffers();
        end
    endtask

    task check_no_side_effect;
        begin
            if (dst_valid_o !== 64'b0 || buffer_release_o !== 4'b0) begin
                $display("ERROR unexpected destination or release side effect");
                errors = errors + 1;
            end
        end
    endtask

    task check_phase_all;
        input integer phase_value;
        begin
            set_legal_command();
            phase_id_i = phase_value;
            #1;
            if (fault_phase_o !== 1'b0 || fault_selector_o !== 1'b0 ||
                fault_buffer_not_ready_o !== 1'b0 ||
                dst_valid_o !== {64{1'b1}} ||
                buffer_release_o !== 4'b1111) begin
                $display("ERROR phase%0d control output", phase_value);
                errors = errors + 1;
            end
            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                source = expected_source_tile(phase_value, tile);
                if (source_tile_sel_o[tile*2 +: 2] !== source[1:0]) begin
                    $display("ERROR phase%0d source select dst=%0d",
                             phase_value, tile);
                    errors = errors + 1;
                end
                for (stream = 0; stream < ACTIVE_STREAMS;
                     stream = stream + 1) begin
                    if (dst_data_o[
                            tile*BUFFER_BITS + stream*SEGMENT_BITS +:
                            SEGMENT_BITS] !==
                        buffer_data_i[
                            source*BUFFER_BITS + stream*SEGMENT_BITS +:
                            SEGMENT_BITS]) begin
                        $display("ERROR phase%0d route dst=%0d stream=%0d",
                                 phase_value, tile, stream);
                        errors = errors + 1;
                    end
                    for (lane = 0; lane < 8; lane = lane + 1) begin
                        expected_byte = source*8'h43 + stream*8'h0B +
                                        lane*8'h1D;
                        if (dst_data_o[
                                tile*BUFFER_BITS + stream*SEGMENT_BITS +
                                lane*8 +: 8] !== expected_byte) begin
                            $display("ERROR lane preservation p=%0d d=%0d s=%0d l=%0d",
                                     phase_value, tile, stream, lane);
                            errors = errors + 1;
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        cmd_valid_i = 1'b0;
        phase_id_i = 8'b0;
        output_row_i = 4'b0;
        output_tile_i = 3'b0;
        buffer_ready_i = 4'b0;
        buffer_age_ok_i = 4'b0;
        buffer_data_i = 4096'b0;
        buffer_dst_meta_i = 24'b0;

        $display("RUN_TEST no_command");
        #1;
        check_no_side_effect();
        if (fault_phase_o !== 1'b0 || fault_selector_o !== 1'b0 ||
            fault_buffer_not_ready_o !== 1'b0) begin
            $display("ERROR no-command fault");
            errors = errors + 1;
        end

        $display("RUN_TEST phase0_full_route");
        check_phase_all(0);
        $display("RUN_TEST phase1_full_route");
        check_phase_all(1);
        $display("RUN_TEST phase2_full_route");
        check_phase_all(2);
        $display("RUN_TEST phase3_full_route_lane_preservation");
        check_phase_all(3);

        $display("RUN_TEST output_row_0_to_7_terminal_release");
        for (row = 0; row < 8; row = row + 1) begin
            set_legal_command();
            phase_id_i = 8'd2;
            output_row_i = row[3:0];
            #1;
            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                source = expected_source_tile(2, tile);
                for (stream = 0; stream < ACTIVE_STREAMS;
                     stream = stream + 1) begin
                    expected_valid = (stream == 2*row) ||
                                     (stream == 2*row + 1);
                    if (dst_valid_o[tile*ACTIVE_STREAMS + stream] !==
                        expected_valid) begin
                        $display("ERROR row valid row=%0d tile=%0d stream=%0d",
                                 row, tile, stream);
                        errors = errors + 1;
                    end
                    if (expected_valid &&
                        dst_data_o[
                            tile*BUFFER_BITS + stream*SEGMENT_BITS +:
                            SEGMENT_BITS] !==
                        buffer_data_i[
                            source*BUFFER_BITS + stream*SEGMENT_BITS +:
                            SEGMENT_BITS]) begin
                        $display("ERROR row data row=%0d tile=%0d stream=%0d",
                                 row, tile, stream);
                        errors = errors + 1;
                    end
                end
            end
            if (buffer_release_o !== ((row == 7) ? 4'b1111 : 4'b0000)) begin
                $display("ERROR terminal release row=%0d", row);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST single_output_tile");
        set_legal_command();
        phase_id_i = 8'd1;
        output_tile_i = 3'd2;
        #1;
        if (dst_valid_o !== {16'h0000, 16'hFFFF, 16'h0000, 16'h0000} ||
            source_tile_sel_o[2*2 +: 2] !== 2'd3 ||
            buffer_release_o !== 4'b1000) begin
            $display("ERROR single output tile routing or release");
            errors = errors + 1;
        end
        for (stream = 0; stream < ACTIVE_STREAMS; stream = stream + 1) begin
            if (dst_data_o[2*BUFFER_BITS + stream*SEGMENT_BITS +:
                           SEGMENT_BITS] !==
                buffer_data_i[3*BUFFER_BITS + stream*SEGMENT_BITS +:
                              SEGMENT_BITS]) begin
                $display("ERROR single tile data stream=%0d", stream);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST buffer_not_ready_fail_closed");
        buffer_ready_i[3] = 1'b0;
        #1;
        if (fault_buffer_not_ready_o !== 1'b1) begin
            $display("ERROR not-ready fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        $display("RUN_TEST buffer_age_violation_fail_closed");
        set_legal_command();
        phase_id_i = 8'd1;
        output_tile_i = 3'd2;
        buffer_age_ok_i[3] = 1'b0;
        #1;
        if (fault_buffer_not_ready_o !== 1'b1) begin
            $display("ERROR age fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        $display("RUN_TEST all_tile_phase0_partial_availability");
        set_legal_command();
        phase_id_i = 8'd0;
        buffer_ready_i = 4'b0001;
        buffer_age_ok_i = 4'b0001;
        #1;
        if (fault_buffer_not_ready_o !== 1'b0 ||
            dst_valid_o !== {48'b0, 16'hFFFF} ||
            buffer_release_o !== 4'b0001) begin
            $display("ERROR phase0 partial availability control");
            errors = errors + 1;
        end
        for (stream = 0; stream < ACTIVE_STREAMS;
             stream = stream + 1) begin
            if (dst_data_o[stream*SEGMENT_BITS +: SEGMENT_BITS] !==
                buffer_data_i[stream*SEGMENT_BITS +: SEGMENT_BITS]) begin
                $display("ERROR phase0 partial route stream=%0d", stream);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST all_tile_phase1_partial_availability");
        set_legal_command();
        phase_id_i = 8'd1;
        buffer_ready_i = 4'b0011;
        buffer_age_ok_i = 4'b0011;
        #1;
        if (fault_buffer_not_ready_o !== 1'b0 ||
            dst_valid_o !== {32'b0, 16'hFFFF, 16'hFFFF} ||
            buffer_release_o !== 4'b0011) begin
            $display("ERROR phase1 partial availability control");
            errors = errors + 1;
        end
        for (stream = 0; stream < ACTIVE_STREAMS;
             stream = stream + 1) begin
            if (dst_data_o[stream*SEGMENT_BITS +: SEGMENT_BITS] !==
                    buffer_data_i[BUFFER_BITS + stream*SEGMENT_BITS +:
                                  SEGMENT_BITS] ||
                dst_data_o[BUFFER_BITS + stream*SEGMENT_BITS +:
                           SEGMENT_BITS] !==
                    buffer_data_i[stream*SEGMENT_BITS +: SEGMENT_BITS]) begin
                $display("ERROR phase1 partial route stream=%0d", stream);
                errors = errors + 1;
            end
        end

        $display("RUN_TEST invalid_phase_4");
        set_legal_command();
        phase_id_i = 8'd4;
        #1;
        if (fault_phase_o !== 1'b1) begin
            $display("ERROR invalid phase4 fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        $display("RUN_TEST invalid_phase_high_bit");
        phase_id_i = 8'h80;
        #1;
        if (fault_phase_o !== 1'b1) begin
            $display("ERROR invalid high phase fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        $display("RUN_TEST invalid_row_selector");
        set_legal_command();
        output_row_i = 4'd9;
        #1;
        if (fault_selector_o !== 1'b1) begin
            $display("ERROR invalid row selector fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        $display("RUN_TEST invalid_tile_selector");
        set_legal_command();
        output_tile_i = 3'd5;
        #1;
        if (fault_selector_o !== 1'b1) begin
            $display("ERROR invalid tile selector fault missing");
            errors = errors + 1;
        end
        check_no_side_effect();

        if (errors == 0) begin
            $display("RTL_SXM_PERMUTE_REGRESSION PASS");
            $finish;
        end

        $display("RTL_SXM_PERMUTE_REGRESSION FAIL errors=%0d", errors);
        $fatal(1);
    end

endmodule
