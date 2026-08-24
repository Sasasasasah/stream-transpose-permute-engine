`timescale 1ns/1ps

module tb_sxm_transpose_superlane_leaf;

    reg clk_i;
    reg rst_ni;
    reg cmd_valid_i;
    reg [95:0] cmd_i;
    reg [5:0] dst_meta_i;
    reg [15:0] src_valid_i;
    reg [1023:0] src_data_i;
    reg buffer_available_i;

    wire [15:0] consume_o;
    wire buffer_write_valid_o;
    wire [1023:0] buffer_write_data_o;
    wire [5:0] buffer_dst_meta_o;
    wire north_cmd_valid_o;
    wire [95:0] north_cmd_o;
    wire [5:0] north_dst_meta_o;
    wire fault_input_invalid_o;
    wire fault_buffer_full_o;

    integer errors;
    integer row;
    integer column;
    integer plane;
    integer out_row;
    integer out_lane;
    reg [7:0] expected_byte;
    reg [95:0] command_a;
    reg [95:0] command_b;

    sxm_transpose_superlane_leaf dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cmd_valid_i(cmd_valid_i),
        .cmd_i(cmd_i),
        .dst_meta_i(dst_meta_i),
        .src_valid_i(src_valid_i),
        .src_data_i(src_data_i),
        .buffer_available_i(buffer_available_i),
        .consume_o(consume_o),
        .buffer_write_valid_o(buffer_write_valid_o),
        .buffer_write_data_o(buffer_write_data_o),
        .buffer_dst_meta_o(buffer_dst_meta_o),
        .north_cmd_valid_o(north_cmd_valid_o),
        .north_cmd_o(north_cmd_o),
        .north_dst_meta_o(north_dst_meta_o),
        .fault_input_invalid_o(fault_input_invalid_o),
        .fault_buffer_full_o(fault_buffer_full_o)
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
            src_valid_i = 16'b0;
            src_data_i = 1024'b0;
            buffer_available_i = 1'b0;
        end
    endtask

    task load_structured_matrix;
        begin
            src_data_i = 1024'b0;
            for (row = 0; row < 8; row = row + 1) begin
                for (column = 0; column < 8; column = column + 1) begin
                    src_data_i[(2*row)*64 + column*8 +: 8] = column[7:0];
                    src_data_i[(2*row+1)*64 + column*8 +: 8] = row[7:0];
                end
            end
        end
    endtask

    task load_unique_matrix;
        begin
            src_data_i = 1024'b0;
            for (plane = 0; plane < 2; plane = plane + 1) begin
                for (row = 0; row < 8; row = row + 1) begin
                    for (column = 0; column < 8;
                         column = column + 1) begin
                        src_data_i[(2*row+plane)*64 + column*8 +: 8] =
                            plane*128 + row*8 + column;
                    end
                end
            end
        end
    endtask

    task check_no_side_effect;
        begin
            if (consume_o !== 16'h0000 ||
                buffer_write_valid_o !== 1'b0) begin
                $display("ERROR unexpected consume or buffer write");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_ni = 1'b0;
        clear_inputs();
        #2;
        rst_ni = 1'b1;
        #1;

        $display("RUN_TEST no_command");
        src_valid_i = 16'hFFFF;
        buffer_available_i = 1'b1;
        #1;
        check_no_side_effect();
        if (fault_input_invalid_o !== 1'b0 ||
            fault_buffer_full_o !== 1'b0) begin
            $display("ERROR no-command local fault");
            errors = errors + 1;
        end

        $display("RUN_TEST structured_matrix_transpose");
        cmd_valid_i = 1'b1;
        cmd_i = 96'h01234567_89ABCDEF_55AA33CC;
        dst_meta_i = 6'h2D;
        src_valid_i = 16'hFFFF;
        buffer_available_i = 1'b1;
        load_structured_matrix();
        #1;
        if (consume_o !== 16'hFFFF ||
            buffer_write_valid_o !== 1'b1 ||
            buffer_dst_meta_o !== 6'h2D ||
            fault_input_invalid_o !== 1'b0 ||
            fault_buffer_full_o !== 1'b0) begin
            $display("ERROR structured capture control");
            errors = errors + 1;
        end
        for (out_row = 0; out_row < 8; out_row = out_row + 1) begin
            for (out_lane = 0; out_lane < 8;
                 out_lane = out_lane + 1) begin
                if (buffer_write_data_o[
                        (2*out_row)*64 + out_lane*8 +: 8] !== out_row[7:0]) begin
                    $display("ERROR structured low row=%0d lane=%0d",
                             out_row, out_lane);
                    errors = errors + 1;
                end
                if (buffer_write_data_o[
                        (2*out_row+1)*64 + out_lane*8 +: 8] !==
                    out_lane[7:0]) begin
                    $display("ERROR structured high row=%0d lane=%0d",
                             out_row, out_lane);
                    errors = errors + 1;
                end
            end
        end

        $display("RUN_TEST fully_unique_byte_pattern");
        load_unique_matrix();
        #1;
        for (plane = 0; plane < 2; plane = plane + 1) begin
            for (out_row = 0; out_row < 8; out_row = out_row + 1) begin
                for (out_lane = 0; out_lane < 8;
                     out_lane = out_lane + 1) begin
                    expected_byte = plane*128 + out_lane*8 + out_row;
                    if (buffer_write_data_o[
                            (2*out_row+plane)*64 + out_lane*8 +: 8] !==
                        expected_byte) begin
                        $display("ERROR unique plane=%0d row=%0d lane=%0d",
                                 plane, out_row, out_lane);
                        errors = errors + 1;
                    end
                end
            end
        end

        $display("RUN_TEST incomplete_valid");
        src_valid_i = 16'hFFFE;
        buffer_available_i = 1'b1;
        #1;
        check_no_side_effect();
        if (fault_input_invalid_o !== 1'b1 ||
            fault_buffer_full_o !== 1'b0) begin
            $display("ERROR stream0 invalid fault");
            errors = errors + 1;
        end
        src_valid_i = 16'hF7FF;
        #1;
        check_no_side_effect();
        if (fault_input_invalid_o !== 1'b1) begin
            $display("ERROR middle-stream invalid fault");
            errors = errors + 1;
        end

        $display("RUN_TEST buffer_full");
        src_valid_i = 16'hFFFF;
        buffer_available_i = 1'b0;
        #1;
        check_no_side_effect();
        if (fault_input_invalid_o !== 1'b0 ||
            fault_buffer_full_o !== 1'b1) begin
            $display("ERROR buffer-full fault");
            errors = errors + 1;
        end

        $display("RUN_TEST dual_fault");
        src_valid_i = 16'hFFDF;
        buffer_available_i = 1'b0;
        #1;
        check_no_side_effect();
        if (fault_input_invalid_o !== 1'b1 ||
            fault_buffer_full_o !== 1'b1) begin
            $display("ERROR dual-fault reporting");
            errors = errors + 1;
        end

        $display("RUN_TEST north_command_propagation");
        @(negedge clk_i);
        rst_ni = 1'b0;
        clear_inputs();
        #1;
        if (north_cmd_valid_o !== 1'b0) begin
            $display("ERROR reset north valid");
            errors = errors + 1;
        end
        rst_ni = 1'b1;
        command_a = 96'hDEADBEEF_11112222_AAAAAAAA;
        cmd_valid_i = 1'b1;
        cmd_i = command_a;
        dst_meta_i = 6'h15;
        src_valid_i = 16'hFFFE;
        buffer_available_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (north_cmd_valid_o !== 1'b1 || north_cmd_o !== command_a ||
            north_dst_meta_o !== 6'h15) begin
            $display("ERROR failed capture command or metadata propagation");
            errors = errors + 1;
        end
        if (fault_input_invalid_o !== 1'b1 ||
            fault_buffer_full_o !== 1'b1) begin
            $display("ERROR propagation test local faults");
            errors = errors + 1;
        end

        $display("RUN_TEST back_to_back_command");
        @(negedge clk_i);
        rst_ni = 1'b0;
        clear_inputs();
        #1;
        rst_ni = 1'b1;
        command_a = 96'h13579BDF_AAAA0001_0000000A;
        command_b = 96'h2468ACE0_BBBB0002_0000000B;
        cmd_valid_i = 1'b1;
        cmd_i = command_a;
        dst_meta_i = 6'h0A;
        src_valid_i = 16'hFFFF;
        buffer_available_i = 1'b1;
        @(posedge clk_i);
        #1;
        if (north_cmd_valid_o !== 1'b1 || north_cmd_o !== command_a ||
            north_dst_meta_o !== 6'h0A) begin
            $display("ERROR back-to-back command A metadata");
            errors = errors + 1;
        end
        @(negedge clk_i);
        cmd_i = command_b;
        dst_meta_i = 6'h2B;
        @(posedge clk_i);
        #1;
        if (north_cmd_valid_o !== 1'b1 || north_cmd_o !== command_b ||
            north_dst_meta_o !== 6'h2B) begin
            $display("ERROR back-to-back command B metadata");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("RTL_SXM_TRANSPOSE_LEAF_REGRESSION PASS");
        else
            $display("RTL_SXM_TRANSPOSE_LEAF_REGRESSION FAIL errors=%0d",
                     errors);
        $finish;
    end

endmodule
