`timescale 1ns/1ps

module tb_sxm_transpose_result_buffer_array;

    localparam integer TILE_ROWS = 4;
    localparam integer DATA_BITS = 1024;
    localparam integer META_BITS = 6;
    localparam integer CYCLE_BITS = 32;

    reg clk_i;
    reg rst_ni;
    reg [TILE_ROWS-1:0] write_valid_i;
    reg [TILE_ROWS*DATA_BITS-1:0] write_data_i;
    reg [TILE_ROWS*META_BITS-1:0] write_dst_meta_i;
    reg [TILE_ROWS-1:0] buffer_release_i;

    wire [TILE_ROWS-1:0] buffer_ready_o;
    wire [TILE_ROWS-1:0] buffer_age_ok_o;
    wire [TILE_ROWS-1:0] buffer_available_o;
    wire [TILE_ROWS*DATA_BITS-1:0] buffer_data_o;
    wire [TILE_ROWS*META_BITS-1:0] buffer_dst_meta_o;
    wire [TILE_ROWS*8-1:0] buffer_input_row_mask_o;
    wire [TILE_ROWS*CYCLE_BITS-1:0] buffer_ready_cycle_o;

    integer errors;
    integer tile;
    integer byte_index;
    integer cycle_index;
    integer expected_write_cycle;
    integer generation;
    reg [7:0] previous_value;

    sxm_transpose_result_buffer_array #(
        .P_TILE_ROWS(TILE_ROWS),
        .P_DATA_BITS(DATA_BITS),
        .P_DST_META_BITS(META_BITS),
        .P_CYCLE_BITS(CYCLE_BITS)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .write_valid_i(write_valid_i),
        .write_data_i(write_data_i),
        .write_dst_meta_i(write_dst_meta_i),
        .buffer_release_i(buffer_release_i),
        .buffer_ready_o(buffer_ready_o),
        .buffer_age_ok_o(buffer_age_ok_o),
        .buffer_available_o(buffer_available_o),
        .buffer_data_o(buffer_data_o),
        .buffer_dst_meta_o(buffer_dst_meta_o),
        .buffer_input_row_mask_o(buffer_input_row_mask_o),
        .buffer_ready_cycle_o(buffer_ready_cycle_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    task clear_cycle_inputs;
        begin
            write_valid_i = {TILE_ROWS{1'b0}};
            write_data_i = {TILE_ROWS*DATA_BITS{1'b0}};
            write_dst_meta_i = {TILE_ROWS*META_BITS{1'b0}};
            buffer_release_i = {TILE_ROWS{1'b0}};
        end
    endtask

    task fill_write_data;
        input integer tile_index;
        input [7:0] value;
        begin
            for (byte_index = 0; byte_index < 128;
                 byte_index = byte_index + 1) begin
                write_data_i[tile_index*DATA_BITS + byte_index*8 +: 8] =
                    value;
            end
        end
    endtask

    task check_buffer_value;
        input integer tile_index;
        input [7:0] value;
        input [5:0] meta;
        begin
            if (buffer_data_o[tile_index*DATA_BITS +: DATA_BITS] !==
                    {128{value}} ||
                buffer_dst_meta_o[tile_index*META_BITS +: META_BITS] !==
                    meta) begin
                $display("ERROR buffer data/meta tile=%0d", tile_index);
                errors = errors + 1;
            end
        end
    endtask

    task commit_cycle;
        begin
            @(posedge clk_i);
            #1;
            cycle_index = cycle_index + 1;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk_i);
            rst_ni = 1'b0;
            clear_cycle_inputs();
            repeat (2) begin
                @(posedge clk_i);
                #1;
            end
            if (buffer_ready_o !== 4'b0000 ||
                buffer_age_ok_o !== 4'b0000 ||
                buffer_available_o !== 4'b1111) begin
                $display("ERROR reset empty state");
                errors = errors + 1;
            end
            @(negedge clk_i);
            rst_ni = 1'b1;
            cycle_index = 0;
            #1;
        end
    endtask

    initial begin
        errors = 0;
        cycle_index = 0;
        rst_ni = 1'b0;
        clear_cycle_inputs();

        $display("RUN_TEST reset_empty_basic_write_age");
        reset_dut();
        write_valid_i[0] = 1'b1;
        fill_write_data(0, 8'hA1);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h11;
        #1;
        if (buffer_ready_o[0] !== 1'b0 ||
            buffer_age_ok_o[0] !== 1'b0 ||
            buffer_available_o[0] !== 1'b1) begin
            $display("ERROR write cycle did not expose old empty state");
            errors = errors + 1;
        end
        expected_write_cycle = cycle_index;
        commit_cycle();
        if (buffer_ready_o[0] !== 1'b1 ||
            buffer_age_ok_o[0] !== 1'b1 ||
            buffer_available_o[0] !== 1'b0 ||
            buffer_input_row_mask_o[0 +: 8] !== 8'hFF ||
            buffer_ready_cycle_o[0*CYCLE_BITS +: CYCLE_BITS] !==
                expected_write_cycle) begin
            $display("ERROR basic write ready age mask cycle");
            errors = errors + 1;
        end
        check_buffer_value(0, 8'hA1, 6'h11);

        $display("RUN_TEST full_protection");
        @(negedge clk_i);
        clear_cycle_inputs();
        write_valid_i[0] = 1'b1;
        fill_write_data(0, 8'hB2);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h22;
        #1;
        if (buffer_available_o[0] !== 1'b0) begin
            $display("ERROR full buffer advertised available");
            errors = errors + 1;
        end
        check_buffer_value(0, 8'hA1, 6'h11);
        commit_cycle();
        check_buffer_value(0, 8'hA1, 6'h11);
        if (buffer_ready_cycle_o[0*CYCLE_BITS +: CYCLE_BITS] !== 0) begin
            $display("ERROR illegal write changed ready_cycle");
            errors = errors + 1;
        end

        $display("RUN_TEST release_only");
        @(negedge clk_i);
        clear_cycle_inputs();
        buffer_release_i[0] = 1'b1;
        #1;
        if (buffer_ready_o[0] !== 1'b1 ||
            buffer_available_o[0] !== 1'b1) begin
            $display("ERROR release cycle availability");
            errors = errors + 1;
        end
        check_buffer_value(0, 8'hA1, 6'h11);
        commit_cycle();
        if (buffer_ready_o[0] !== 1'b0 ||
            buffer_age_ok_o[0] !== 1'b0 ||
            buffer_available_o[0] !== 1'b1) begin
            $display("ERROR release-only next state");
            errors = errors + 1;
        end

        $display("RUN_TEST same_cycle_release_write_read_old_write_new");
        reset_dut();
        write_valid_i[0] = 1'b1;
        fill_write_data(0, 8'hA3);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h13;
        commit_cycle();
        @(negedge clk_i);
        clear_cycle_inputs();
        buffer_release_i[0] = 1'b1;
        write_valid_i[0] = 1'b1;
        fill_write_data(0, 8'hB4);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h24;
        #1;
        if (buffer_available_o[0] !== 1'b1 ||
            buffer_age_ok_o[0] !== 1'b1) begin
            $display("ERROR reuse cycle availability or OLD age");
            errors = errors + 1;
        end
        check_buffer_value(0, 8'hA3, 6'h13);
        expected_write_cycle = cycle_index;
        commit_cycle();
        if (buffer_ready_o[0] !== 1'b1 ||
            buffer_age_ok_o[0] !== 1'b1 ||
            buffer_ready_cycle_o[0*CYCLE_BITS +: CYCLE_BITS] !==
                expected_write_cycle) begin
            $display("ERROR reuse NEW ready age cycle");
            errors = errors + 1;
        end
        check_buffer_value(0, 8'hB4, 6'h24);

        $display("RUN_TEST four_tile_independence_metadata");
        reset_dut();
        write_valid_i = 4'b0111;
        fill_write_data(0, 8'h10);
        fill_write_data(1, 8'h21);
        fill_write_data(2, 8'h32);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h01;
        write_dst_meta_i[1*META_BITS +: META_BITS] = 6'h12;
        write_dst_meta_i[2*META_BITS +: META_BITS] = 6'h23;
        commit_cycle();
        @(negedge clk_i);
        clear_cycle_inputs();
        buffer_release_i = 4'b0101;
        write_valid_i = 4'b1001;
        fill_write_data(0, 8'h40);
        fill_write_data(3, 8'h73);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h34;
        write_dst_meta_i[3*META_BITS +: META_BITS] = 6'h3D;
        #1;
        if (buffer_available_o !== 4'b1101) begin
            $display("ERROR four-tile availability expected=1101 actual=%b",
                     buffer_available_o);
            errors = errors + 1;
        end
        commit_cycle();
        if (buffer_ready_o !== 4'b1011) begin
            $display("ERROR four-tile ready expected=1011 actual=%b",
                     buffer_ready_o);
            errors = errors + 1;
        end
        check_buffer_value(0, 8'h40, 6'h34);
        check_buffer_value(1, 8'h21, 6'h12);
        check_buffer_value(2, 8'h32, 6'h23);
        check_buffer_value(3, 8'h73, 6'h3D);

        $display("RUN_TEST repeated_single_buffer_reuse");
        reset_dut();
        write_valid_i[0] = 1'b1;
        fill_write_data(0, 8'h80);
        write_dst_meta_i[0*META_BITS +: META_BITS] = 6'h08;
        commit_cycle();
        previous_value = 8'h80;
        for (generation = 0; generation < 3;
             generation = generation + 1) begin
            @(negedge clk_i);
            clear_cycle_inputs();
            buffer_release_i[0] = 1'b1;
            write_valid_i[0] = 1'b1;
            fill_write_data(0, 8'h90 + generation);
            write_dst_meta_i[0*META_BITS +: META_BITS] =
                6'h20 + generation;
            #1;
            check_buffer_value(0, previous_value,
                               (generation == 0) ? 6'h08 :
                               (6'h20 + generation - 1));
            expected_write_cycle = cycle_index;
            commit_cycle();
            check_buffer_value(0, 8'h90 + generation,
                               6'h20 + generation);
            if (buffer_ready_o[0] !== 1'b1 ||
                buffer_age_ok_o[0] !== 1'b1 ||
                buffer_ready_cycle_o[0*CYCLE_BITS +: CYCLE_BITS] !==
                    expected_write_cycle) begin
                $display("ERROR repeated reuse generation=%0d", generation);
                errors = errors + 1;
            end
            previous_value = 8'h90 + generation;
        end

        $display("RUN_TEST per_tile_ready_cycle_integrity");
        reset_dut();
        for (tile = 0; tile < TILE_ROWS; tile = tile + 1) begin
            if (tile != 0)
                @(negedge clk_i);
            clear_cycle_inputs();
            write_valid_i[tile] = 1'b1;
            fill_write_data(tile, 8'hC0 + tile);
            write_dst_meta_i[tile*META_BITS +: META_BITS] = tile + 1;
            expected_write_cycle = cycle_index;
            commit_cycle();
            if (buffer_ready_cycle_o[
                    tile*CYCLE_BITS +: CYCLE_BITS] !==
                expected_write_cycle) begin
                $display("ERROR ready_cycle tile=%0d expected=%0d actual=%0d",
                         tile, expected_write_cycle,
                         buffer_ready_cycle_o[
                             tile*CYCLE_BITS +: CYCLE_BITS]);
                errors = errors + 1;
            end
        end
        if (buffer_ready_cycle_o !== {32'd3, 32'd2, 32'd1, 32'd0}) begin
            $display("ERROR packed ready_cycle integrity");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("RTL_SXM_RESULT_BUFFER_REGRESSION PASS");
            $finish;
        end

        $display("RTL_SXM_RESULT_BUFFER_REGRESSION FAIL errors=%0d", errors);
        $fatal(1);
    end

endmodule
