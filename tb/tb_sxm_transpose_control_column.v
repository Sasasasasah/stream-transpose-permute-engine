`timescale 1ns/1ps

module tb_sxm_transpose_control_column;

    localparam integer TILE_ROWS = 4;

    reg clk_i;
    reg rst_ni;
    reg cmd_valid_i;
    reg [95:0] cmd_i;
    reg [5:0] dst_meta_i;
    reg [TILE_ROWS*16-1:0] tile_src_valid_i;
    reg [TILE_ROWS*1024-1:0] tile_src_data_i;
    reg [TILE_ROWS-1:0] tile_buffer_available_i;

    wire [TILE_ROWS*16-1:0] tile_consume_o;
    wire [TILE_ROWS-1:0] tile_buffer_write_valid_o;
    wire [TILE_ROWS*1024-1:0] tile_buffer_write_data_o;
    wire [TILE_ROWS*6-1:0] tile_buffer_dst_meta_o;
    wire [TILE_ROWS-1:0] tile_fault_input_invalid_o;
    wire [TILE_ROWS-1:0] tile_fault_buffer_full_o;
    wire [TILE_ROWS-1:0] stage_cmd_valid_o;
    wire [TILE_ROWS*96-1:0] stage_cmd_o;
    wire [TILE_ROWS*6-1:0] stage_dst_meta_o;

    integer errors;
    integer tile;
    integer byte_index;

    reg history_valid0;
    reg history_valid1;
    reg history_valid2;
    reg [95:0] history_cmd0;
    reg [95:0] history_cmd1;
    reg [95:0] history_cmd2;
    reg [5:0] history_meta0;
    reg [5:0] history_meta1;
    reg [5:0] history_meta2;

    reg [95:0] command_a;
    reg [95:0] command_b;
    reg [95:0] command_c;
    reg [95:0] command_d;
    reg [95:0] command_e;
    reg [95:0] command_f;

    sxm_transpose_control_column #(
        .P_TILE_ROWS(TILE_ROWS)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cmd_valid_i(cmd_valid_i),
        .cmd_i(cmd_i),
        .dst_meta_i(dst_meta_i),
        .tile_src_valid_i(tile_src_valid_i),
        .tile_src_data_i(tile_src_data_i),
        .tile_buffer_available_i(tile_buffer_available_i),
        .tile_consume_o(tile_consume_o),
        .tile_buffer_write_valid_o(tile_buffer_write_valid_o),
        .tile_buffer_write_data_o(tile_buffer_write_data_o),
        .tile_buffer_dst_meta_o(tile_buffer_dst_meta_o),
        .tile_fault_input_invalid_o(tile_fault_input_invalid_o),
        .tile_fault_buffer_full_o(tile_fault_buffer_full_o),
        .stage_cmd_valid_o(stage_cmd_valid_o),
        .stage_cmd_o(stage_cmd_o),
        .stage_dst_meta_o(stage_dst_meta_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    task clear_inputs;
        begin
            cmd_valid_i = 1'b0;
            cmd_i = 96'b0;
            dst_meta_i = 6'b0;
            tile_src_valid_i = {TILE_ROWS*16{1'b0}};
            tile_src_data_i = {TILE_ROWS*1024{1'b0}};
            tile_buffer_available_i = {TILE_ROWS{1'b0}};
        end
    endtask

    task clear_history;
        begin
            history_valid0 = 1'b0;
            history_valid1 = 1'b0;
            history_valid2 = 1'b0;
            history_cmd0 = 96'b0;
            history_cmd1 = 96'b0;
            history_cmd2 = 96'b0;
            history_meta0 = 6'b0;
            history_meta1 = 6'b0;
            history_meta2 = 6'b0;
        end
    endtask

    task enable_all_tiles;
        begin
            tile_src_valid_i = {TILE_ROWS{16'hFFFF}};
            tile_buffer_available_i = {TILE_ROWS{1'b1}};
        end
    endtask

    task fill_tile_data;
        input integer tile_index;
        input [7:0] value;
        begin
            for (byte_index = 0; byte_index < 128;
                 byte_index = byte_index + 1) begin
                tile_src_data_i[tile_index*1024 + byte_index*8 +: 8] =
                    value;
            end
        end
    endtask

    task check_stages;
        begin
            if (stage_cmd_valid_o !==
                {history_valid2, history_valid1, history_valid0,
                 cmd_valid_i}) begin
                $display("ERROR stage valid timing expected=%b actual=%b",
                         {history_valid2, history_valid1, history_valid0,
                          cmd_valid_i}, stage_cmd_valid_o);
                errors = errors + 1;
            end
            if (stage_cmd_o[0*96 +: 96] !== cmd_i ||
                stage_dst_meta_o[0*6 +: 6] !== dst_meta_i) begin
                $display("ERROR stage0 command metadata mismatch");
                errors = errors + 1;
            end
            if (stage_cmd_o[1*96 +: 96] !== history_cmd0 ||
                stage_dst_meta_o[1*6 +: 6] !== history_meta0) begin
                $display("ERROR stage1 command metadata mismatch");
                errors = errors + 1;
            end
            if (stage_cmd_o[2*96 +: 96] !== history_cmd1 ||
                stage_dst_meta_o[2*6 +: 6] !== history_meta1) begin
                $display("ERROR stage2 command metadata mismatch");
                errors = errors + 1;
            end
            if (stage_cmd_o[3*96 +: 96] !== history_cmd2 ||
                stage_dst_meta_o[3*6 +: 6] !== history_meta2) begin
                $display("ERROR stage3 command metadata mismatch");
                errors = errors + 1;
            end
        end
    endtask

    task begin_cycle;
        input valid_value;
        input [95:0] command_value;
        input [5:0] meta_value;
        begin
            @(negedge clk_i);
            cmd_valid_i = valid_value;
            cmd_i = command_value;
            dst_meta_i = meta_value;
            #1;
            check_stages();
        end
    endtask

    task end_cycle;
        begin
            @(posedge clk_i);
            #1;
            history_valid2 = history_valid1;
            history_valid1 = history_valid0;
            history_valid0 = cmd_valid_i;
            history_cmd2 = history_cmd1;
            history_cmd1 = history_cmd0;
            history_cmd0 = cmd_i;
            history_meta2 = history_meta1;
            history_meta1 = history_meta0;
            history_meta0 = dst_meta_i;
        end
    endtask

    task reset_column;
        begin
            @(negedge clk_i);
            rst_ni = 1'b0;
            clear_inputs();
            clear_history();
            #1;
            if (stage_cmd_valid_o !== 4'b0000) begin
                $display("ERROR reset stage valid before edge");
                errors = errors + 1;
            end
            @(posedge clk_i);
            #1;
            if (stage_cmd_valid_o !== 4'b0000) begin
                $display("ERROR reset stage valid after edge");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            #1;
        end
    endtask

    task check_uniform_tile_outputs;
        input [7:0] base_value;
        reg [7:0] expected;
        begin
            for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
                expected = base_value + tile;
                if (tile_buffer_write_valid_o[tile] !== 1'b1 ||
                    tile_consume_o[tile*16 +: 16] !== 16'hFFFF ||
                    tile_buffer_write_data_o[tile*1024 +: 8] !== expected ||
                    tile_buffer_write_data_o[tile*1024+1016 +: 8] !==
                        expected ||
                    tile_buffer_dst_meta_o[tile*6 +: 6] !==
                        stage_dst_meta_o[tile*6 +: 6]) begin
                    $display("ERROR tile-local current data tile=%0d", tile);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b0;
        clear_inputs();
        clear_history();
        command_a = 96'hAAAA0000_AAAA0000_0000000A;
        command_b = 96'hBBBB0000_BBBB0000_0000000B;
        command_c = 96'hCCCC0000_CCCC0000_0000000C;
        command_d = 96'hDDDD0000_DDDD0000_0000000D;
        command_e = 96'hEEEE0000_EEEE0000_0000000E;
        command_f = 96'hFFFF0000_FFFF0000_0000000F;

        $display("RUN_TEST single_command_exact_timing");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_a, 6'h01); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();

        $display("RUN_TEST bubble_preservation");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_a, 6'h02); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b1, command_b, 6'h03); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();

        $display("RUN_TEST back_to_back_ii1_metadata_alignment");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_a, 6'h0A); end_cycle();
        begin_cycle(1'b1, command_b, 6'h0B); end_cycle();
        begin_cycle(1'b1, command_c, 6'h0C); end_cycle();
        begin_cycle(1'b1, command_d, 6'h0D);
        if (stage_cmd_valid_o !== 4'b1111) begin
            $display("ERROR pipeline did not reach four-command occupancy");
            errors = errors + 1;
        end
        end_cycle();
        begin_cycle(1'b1, command_e, 6'h0E); end_cycle();
        begin_cycle(1'b1, command_f, 6'h0F); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();
        begin_cycle(1'b0, 96'b0, 6'h00); end_cycle();

        $display("RUN_TEST tile0_failed_capture_no_stall");
        reset_column();
        enable_all_tiles();
        tile_src_valid_i[0 +: 16] = 16'hFFFE;
        begin_cycle(1'b1, command_a, 6'h15);
        if (tile_fault_input_invalid_o[0] !== 1'b1 ||
            tile_buffer_write_valid_o[0] !== 1'b0 ||
            tile_consume_o[0 +: 16] !== 16'h0000) begin
            $display("ERROR tile0 failed-capture behavior");
            errors = errors + 1;
        end
        end_cycle();
        tile_src_valid_i[0 +: 16] = 16'hFFFF;
        begin_cycle(1'b0, 96'b0, 6'h00);
        if (stage_cmd_valid_o[1] !== 1'b1 ||
            stage_cmd_o[1*96 +: 96] !== command_a ||
            stage_dst_meta_o[1*6 +: 6] !== 6'h15) begin
            $display("ERROR tile0 failure stalled command");
            errors = errors + 1;
        end
        end_cycle();

        $display("RUN_TEST middle_tile_full_no_stall");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_a, 6'h21); end_cycle();
        tile_buffer_available_i[1] = 1'b0;
        begin_cycle(1'b0, 96'b0, 6'h00);
        if (tile_fault_buffer_full_o[1] !== 1'b1 ||
            tile_buffer_write_valid_o[1] !== 1'b0 ||
            tile_consume_o[1*16 +: 16] !== 16'h0000) begin
            $display("ERROR middle tile full behavior");
            errors = errors + 1;
        end
        end_cycle();
        tile_buffer_available_i[1] = 1'b1;
        begin_cycle(1'b0, 96'b0, 6'h00);
        if (stage_cmd_valid_o[2] !== 1'b1 ||
            stage_cmd_o[2*96 +: 96] !== command_a ||
            stage_dst_meta_o[2*6 +: 6] !== 6'h21) begin
            $display("ERROR middle tile failure stalled command");
            errors = errors + 1;
        end
        end_cycle();

        $display("RUN_TEST per_tile_current_cycle_data");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_a, 6'h31); end_cycle();
        begin_cycle(1'b1, command_b, 6'h32); end_cycle();
        begin_cycle(1'b1, command_c, 6'h33); end_cycle();
        for (tile = 0; tile < TILE_ROWS; tile = tile + 1)
            fill_tile_data(tile, 8'h10 + tile);
        begin_cycle(1'b1, command_d, 6'h34);
        check_uniform_tile_outputs(8'h10);
        end_cycle();
        for (tile = 0; tile < TILE_ROWS; tile = tile + 1)
            fill_tile_data(tile, 8'h40 + tile);
        begin_cycle(1'b1, command_e, 6'h35);
        check_uniform_tile_outputs(8'h40);
        end_cycle();

        $display("RUN_TEST reset_and_restart");
        reset_column();
        enable_all_tiles();
        begin_cycle(1'b1, command_f, 6'h3F);
        if (stage_cmd_valid_o[0] !== 1'b1 ||
            stage_cmd_o[0 +: 96] !== command_f ||
            stage_dst_meta_o[0 +: 6] !== 6'h3F) begin
            $display("ERROR command did not enter tile0 after reset");
            errors = errors + 1;
        end
        end_cycle();

        if (errors == 0) begin
            $display("RTL_SXM_TRANSPOSE_CONTROL_REGRESSION PASS");
            $finish;
        end

        $display("RTL_SXM_TRANSPOSE_CONTROL_REGRESSION FAIL errors=%0d",
                 errors);
        $fatal(1);
    end

endmodule
