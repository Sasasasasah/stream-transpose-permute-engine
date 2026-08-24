#include "sxm_slice_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>

namespace {

using Model = SxmSliceModel;
using Matrix = std::array<std::uint16_t, 1024>;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

Model::Command make_command(const std::uint8_t opcode,
                            const bool src_direction,
                            const std::uint8_t src_base,
                            const bool dst_direction,
                            const std::uint8_t dst_base,
                            const std::uint8_t input_row,
                            const std::uint8_t output_row,
                            const std::uint8_t output_tile,
                            const std::uint8_t phase) {
    std::uint64_t low = 0;
    low |= static_cast<std::uint64_t>(opcode & 0x3U);
    low |= static_cast<std::uint64_t>(src_direction) << 2U;
    low |= static_cast<std::uint64_t>(src_base & 0x1FU) << 3U;
    low |= static_cast<std::uint64_t>(dst_direction) << 8U;
    low |= static_cast<std::uint64_t>(dst_base & 0x1FU) << 9U;
    low |= static_cast<std::uint64_t>(input_row & 0xFU) << 14U;
    low |= static_cast<std::uint64_t>(output_row & 0xFU) << 18U;
    low |= static_cast<std::uint64_t>(output_tile & 0x7U) << 22U;
    low |= static_cast<std::uint64_t>(phase) << 25U;
    return Model::Command{static_cast<std::uint32_t>(low),
                          static_cast<std::uint32_t>(low >> 32U), 0U};
}

std::uint8_t byte_at(const std::uint64_t segment, const std::size_t lane) {
    return static_cast<std::uint8_t>((segment >> (lane * 8U)) & 0xFFU);
}

void put_byte(std::uint64_t& segment, const std::size_t lane,
              const std::uint8_t value) {
    const auto shift = static_cast<std::uint64_t>(lane * 8U);
    segment |= static_cast<std::uint64_t>(value) << shift;
}

int capture_owner(const int wave, const int tile, const bool continuous) {
    if (wave >= tile && wave <= tile + 3) {
        return 0;
    }
    if (continuous && wave >= tile + 4 && wave <= tile + 7) {
        return 1;
    }
    return -1;
}

int capture_block_row(const int wave, const int tile, const int owner) {
    return owner == 0 ? wave - tile : wave - 4 - tile;
}

Matrix transpose_matrix(const Matrix& input) {
    Matrix output{};
    for (std::size_t row = 0; row < 32U; ++row) {
        for (std::size_t column = 0; column < 32U; ++column) {
            output[row * 32U + column] = input[column * 32U + row];
        }
    }
    return output;
}

void fill_capture_inputs(Model::Inputs& inputs, const int wave,
                         const bool continuous, const Matrix& matrix_a,
                         const Matrix& matrix_b) {
    for (int tile = 0; tile < 4; ++tile) {
        const int owner = capture_owner(wave, tile, continuous);
        if (owner < 0) {
            continue;
        }
        const int block_row = capture_block_row(wave, tile, owner);
        inputs.sr_read_valid[static_cast<std::size_t>(tile)] = 0xFFFFU;
        const Matrix& matrix = owner == 0 ? matrix_a : matrix_b;
        for (std::size_t row = 0; row < 8U; ++row) {
            for (std::size_t lane = 0; lane < 8U; ++lane) {
                const auto value = matrix[
                    (8U * static_cast<std::size_t>(block_row) + row) * 32U +
                    8U * static_cast<std::size_t>(tile) + lane];
                put_byte(inputs.sr_read_data[tile][2U * row], lane,
                         static_cast<std::uint8_t>(value & 0xFFU));
                put_byte(inputs.sr_read_data[tile][2U * row + 1U], lane,
                         static_cast<std::uint8_t>(value >> 8U));
            }
        }
    }
}

std::uint8_t bool_mask(const Model::TileBool& values) {
    std::uint8_t mask = 0;
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        if (values[tile]) {
            mask |= static_cast<std::uint8_t>(1U << tile);
        }
    }
    return mask;
}

std::uint64_t consume_mask(const Model::TileMask& values) {
    std::uint64_t mask = 0;
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        mask |= static_cast<std::uint64_t>(values[tile]) << (tile * 16U);
    }
    return mask;
}

std::uint64_t write_valid_mask(const Model::WriteValid& values) {
    std::uint64_t mask = 0;
    for (std::size_t tile = 0; tile < 4U; ++tile) {
        for (std::size_t stream = 0; stream < 16U; ++stream) {
            if (values[tile][stream]) {
                mask |= std::uint64_t{1} << (tile * 16U + stream);
            }
        }
    }
    return mask;
}

void write_trace(std::ofstream& trace, const Model::Observation& output) {
    trace << "CYCLE=" << std::dec << output.cycle
          << " STAGE=" << std::hex << static_cast<unsigned>(
                 bool_mask(output.stage_valid))
          << " CONSUME=" << std::setw(16) << std::setfill('0')
          << consume_mask(output.consume)
          << " READY=" << static_cast<unsigned>(
                 bool_mask(output.buffer_ready))
          << " AGE=" << static_cast<unsigned>(
                 bool_mask(output.buffer_age_ok))
          << " WRITE=" << std::setw(16) << std::setfill('0')
          << write_valid_mask(output.write_valid)
          << " FAULT=" << static_cast<unsigned>(output.fault_valid)
          << " BUSY=" << static_cast<unsigned>(output.busy) << '\n';
}

void test_basic_slice() {
    std::cout << "RUN_TEST cmodel_sxm_slice_basic" << '\n';
    Model model;
    model.reset();

    Model::Inputs idle{};
    auto output = model.step(idle);
    expect(bool_mask(output.stage_valid) == 0U &&
               bool_mask(output.buffer_ready) == 0U && !output.busy &&
               consume_mask(output.consume) == 0U &&
               write_valid_mask(output.write_valid) == 0U &&
               !output.fault_valid,
           "reset/idle observation mismatch");

    model.reset();
    const auto command_a = make_command(0U, false, 16U, true, 0U,
                                        8U, 0U, 0U, 0U);
    const auto command_b = make_command(0U, false, 8U, true, 0U,
                                        8U, 0U, 0U, 0U);
    const auto command_c = make_command(0U, true, 4U, true, 0U,
                                        8U, 0U, 0U, 0U);
    const auto command_d = make_command(0U, false, 0U, true, 0U,
                                        8U, 0U, 0U, 0U);
    for (const auto& command : {command_a, command_b, command_c}) {
        Model::Inputs input{};
        input.transpose_cmd_valid = true;
        input.transpose_cmd = command;
        model.step(input);
    }
    Model::Inputs selector_input{};
    selector_input.transpose_cmd_valid = true;
    selector_input.transpose_cmd = command_d;
    output = model.step(selector_input);
    for (std::size_t stream = 0; stream < 16U; ++stream) {
        expect(output.read_selector[0][stream] == stream,
               "tile0 selector mismatch");
        expect(output.read_selector[1][stream] == 0x20U + 4U + stream,
               "tile1 selector mismatch");
        expect(output.read_selector[2][stream] == 8U + stream,
               "tile2 selector mismatch");
        expect(output.read_selector[3][stream] == 16U + stream,
               "tile3 selector mismatch");
    }

    model.reset();
    Model::Inputs capture{};
    capture.transpose_cmd_valid = true;
    capture.transpose_cmd = make_command(0U, false, 0U, true, 8U,
                                         8U, 0U, 0U, 0U);
    capture.sr_read_valid[0] = 0xFFFFU;
    for (std::size_t stream = 0; stream < 16U; ++stream) {
        for (std::size_t lane = 0; lane < 8U; ++lane) {
            put_byte(capture.sr_read_data[0][stream], lane,
                     static_cast<std::uint8_t>(stream * 11U + lane));
        }
    }
    output = model.step(capture);
    expect(output.consume[0] == 0xFFFFU && !output.fault_valid,
           "transpose capture intent mismatch");
    auto state = model.buffer_state();
    expect(state.buffer_ready[0] && state.buffer_dst_meta[0] == 0x28U,
           "transpose buffer state/meta mismatch");

    Model::Inputs permute{};
    permute.permute_cmd_valid = true;
    permute.permute_cmd = make_command(1U, true, 8U, false, 16U,
                                       0U, 8U, 4U, 0U);
    // The original Transpose command has advanced to tile1 in this cycle.
    // Supply its legal SR response so this test isolates Buffer -> Permute.
    permute.sr_read_valid[1] = 0xFFFFU;
    output = model.step(permute);
    expect(output.write_valid[0][0] &&
               output.write_data[0] == state.buffer_data[0] &&
               output.write_selector[0] == 16U && !output.fault_valid,
           "buffer-to-Permute output mismatch");
    expect(!model.buffer_state().buffer_ready[0],
           "Permute terminal release mismatch");

    model.reset();
    output = model.step(capture);
    const auto old_data = model.buffer_state().buffer_data[0];
    Model::Inputs replace = capture;
    replace.permute_cmd_valid = true;
    replace.permute_cmd = permute.permute_cmd;
    replace.sr_read_valid[1] = 0xFFFFU;
    for (auto& segment : replace.sr_read_data[0]) {
        segment = 0x5A5A5A5A5A5A5A5AULL;
    }
    output = model.step(replace);
    expect(output.write_data[0] == old_data &&
               !output.transpose_buffer_full[0] && !output.fault_valid,
           "same-cycle OLD read failed");
    state = model.buffer_state();
    expect(state.buffer_ready[0] && state.buffer_age_ok[0] &&
               state.buffer_data[0] != old_data,
           "same-cycle NEW commit/age failed");

    if (failures == 0) {
        std::cout << "CMODEL_SXM_SLICE_BASIC PASS" << '\n';
    }
}

void test_command_legality() {
    std::cout << "RUN_TEST cmodel_sxm_command_legality" << '\n';
    const int before = failures;
    const auto legal_transpose = make_command(0U, false, 0U, true, 8U,
                                              8U, 0U, 0U, 0U);

    std::array<Model::Command, 5> invalid_transpose{
        make_command(0U, false, 17U, true, 8U, 8U, 0U, 0U, 0U),
        make_command(0U, false, 0U, true, 17U, 8U, 0U, 0U, 0U),
        make_command(1U, false, 0U, true, 8U, 8U, 0U, 0U, 0U),
        make_command(0U, false, 0U, true, 8U, 7U, 0U, 0U, 0U),
        legal_transpose
    };
    invalid_transpose[4][1] |= 0x2U;  // reserved bit 33

    for (const auto& command : invalid_transpose) {
        Model model;
        model.reset();
        Model::Inputs input{};
        input.transpose_cmd_valid = true;
        input.transpose_cmd = command;
        input.sr_read_valid[0] = 0xFFFFU;
        const auto output = model.step(input);
        expect(output.fault_valid && !output.stage_valid[0] &&
                   output.consume[0] == 0U &&
                   output.read_selector[0][0] == 0U &&
                   !model.buffer_state().buffer_ready[0],
               "invalid Transpose command did not fail closed");
    }

    // Faults are pulses, not recovery state: the next legal issue proceeds.
    Model no_stall_model;
    no_stall_model.reset();
    Model::Inputs invalid{};
    invalid.transpose_cmd_valid = true;
    invalid.transpose_cmd = invalid_transpose[0];
    invalid.sr_read_valid[0] = 0xFFFFU;
    no_stall_model.step(invalid);
    Model::Inputs legal{};
    legal.transpose_cmd_valid = true;
    legal.transpose_cmd = legal_transpose;
    legal.sr_read_valid[0] = 0xFFFFU;
    auto output = no_stall_model.step(legal);
    expect(!output.fault_valid && output.stage_valid[0] &&
               output.consume[0] == 0xFFFFU,
           "legal command stalled after command fault");

    const std::array<Model::Command, 4> invalid_permute{
        make_command(1U, false, 0U, false, 17U, 0U, 8U, 0U, 0U),
        make_command(0U, false, 0U, false, 16U, 0U, 8U, 0U, 0U),
        make_command(1U, false, 17U, false, 16U, 0U, 8U, 0U, 0U),
        Model::Command{}
    };
    for (std::size_t index = 0; index < invalid_permute.size(); ++index) {
        Model model;
        model.reset();
        Model::Inputs capture{};
        capture.transpose_cmd_valid = true;
        capture.transpose_cmd = legal_transpose;
        capture.sr_read_valid[0] = 0xFFFFU;
        model.step(capture);

        Model::Inputs permute{};
        permute.permute_cmd_valid = true;
        permute.permute_cmd = invalid_permute[index];
        if (index == 3U) {
            permute.permute_cmd = make_command(
                1U, false, 0U, false, 16U, 0U, 8U, 0U, 0U);
            permute.permute_cmd[2] = 1U;
        }
        // The legal Transpose has advanced to tile1.
        permute.sr_read_valid[1] = 0xFFFFU;
        output = model.step(permute);
        expect(output.fault_valid &&
                   write_valid_mask(output.write_valid) == 0U &&
                   model.buffer_state().buffer_ready[0],
               "invalid Permute command did not fail closed");
    }

    if (failures == before) {
        std::cout << "CMODEL_SXM_COMMAND_LEGALITY PASS" << '\n';
    }
}

struct MatrixResult {
    std::array<int, 16> seen_a{};
    std::array<int, 16> seen_b{};
    int elements_a = 0;
    int elements_b = 0;
};

void verify_wave(const Model::Observation& output, const int wave,
                 const bool continuous, const Matrix& expected_a,
                 const Matrix& expected_b, MatrixResult& result) {
    std::array<bool, 4> expected_destinations{};
    for (int tile = 0; tile < 4; ++tile) {
        const int owner = capture_owner(wave, tile, continuous);
        if (owner >= 0) {
            expected_destinations[static_cast<std::size_t>(
                capture_block_row(wave, tile, owner))] = true;
        }
    }
    for (std::size_t destination = 0; destination < 4U; ++destination) {
        for (std::size_t stream = 0; stream < 16U; ++stream) {
            expect(output.write_valid[destination][stream] ==
                       expected_destinations[destination],
                   "matrix destination valid mismatch");
        }
    }

    for (int tile = 0; tile < 4; ++tile) {
        const int owner = capture_owner(wave, tile, continuous);
        if (owner < 0) {
            continue;
        }
        const int block_row = capture_block_row(wave, tile, owner);
        const int block_index = block_row * 4 + tile;
        if (owner == 0) {
            ++result.seen_a[static_cast<std::size_t>(block_index)];
        } else {
            ++result.seen_b[static_cast<std::size_t>(block_index)];
        }
        const Matrix& expected = owner == 0 ? expected_a : expected_b;
        for (std::size_t row = 0; row < 8U; ++row) {
            for (std::size_t lane = 0; lane < 8U; ++lane) {
                const auto index = (8U * static_cast<std::size_t>(tile) + row) *
                    32U + 8U * static_cast<std::size_t>(block_row) + lane;
                const auto actual = static_cast<std::uint16_t>(
                    byte_at(output.write_data[block_row][2U * row], lane) |
                    (static_cast<std::uint16_t>(byte_at(
                        output.write_data[block_row][2U * row + 1U], lane))
                     << 8U));
                expect(actual == expected[index],
                       "matrix transposed element mismatch");
                if (owner == 0) {
                    ++result.elements_a;
                } else {
                    ++result.elements_b;
                }
            }
        }
    }
}

void run_matrix_case(const bool continuous, const Matrix& matrix_a,
                     const Matrix& matrix_b, const Matrix& expected_a,
                     const Matrix& expected_b) {
    Model model;
    model.reset();
    MatrixResult result{};
    std::ofstream trace;
    if (continuous) {
        trace.open("sim/sxm_cmodel_trace.txt", std::ios::trunc);
        expect(trace.is_open(), "cannot open CModel trace");
    }

    const int last_cycle = continuous ? 11 : 7;
    for (int cycle = 0; cycle <= last_cycle; ++cycle) {
        Model::Inputs inputs{};
        inputs.transpose_cmd_valid = cycle < 4 ||
            (continuous && cycle >= 4 && cycle < 8);
        inputs.transpose_cmd = make_command(0U, false, 0U, true, 0U,
                                            8U, 0U, 0U, 0U);
        if (cycle > 0) {
            inputs.permute_cmd_valid = true;
            inputs.permute_cmd = make_command(
                1U, true, 0U, false, 16U, 0U, 8U, 4U,
                static_cast<std::uint8_t>((cycle - 1) & 3));
        }
        fill_capture_inputs(inputs, cycle, continuous, matrix_a, matrix_b);
        const auto output = model.step(inputs);
        if (continuous) {
            write_trace(trace, output);
        }
        expect(!output.fault_valid &&
                   bool_mask(output.transpose_input_invalid) == 0U &&
                   bool_mask(output.transpose_buffer_full) == 0U,
               "legal matrix schedule fault");
        for (int tile = 0; tile < 4; ++tile) {
            const bool active = capture_owner(cycle, tile, continuous) >= 0;
            expect(output.consume[static_cast<std::size_t>(tile)] ==
                       (active ? 0xFFFFU : 0U),
                   "matrix consume mismatch");
        }
        if (cycle > 0) {
            verify_wave(output, cycle - 1, continuous, expected_a,
                        expected_b, result);
        }
        if (continuous && cycle == 4) {
            const auto state = model.buffer_state();
            expect(state.buffer_ready[0] && result.seen_b[0] == 0,
                   "wave4 NEW buffer visibility/order mismatch");
            for (std::size_t row = 0; row < 8U; ++row) {
                for (std::size_t lane = 0; lane < 8U; ++lane) {
                    const auto actual = static_cast<std::uint16_t>(
                        byte_at(state.buffer_data[0][2U * row], lane) |
                        (static_cast<std::uint16_t>(byte_at(
                            state.buffer_data[0][2U * row + 1U], lane))
                         << 8U));
                    expect(actual == expected_b[row * 32U + lane],
                           "wave4 NEW B.B00 commit mismatch");
                }
            }
        }
    }

    for (std::size_t block = 0; block < 16U; ++block) {
        expect(result.seen_a[block] == 1, "matrix A block count mismatch");
        if (continuous) {
            expect(result.seen_b[block] == 1,
                   "matrix B block count mismatch");
        }
    }
    expect(result.elements_a == 1024, "matrix A element count mismatch");
    if (continuous) {
        expect(result.elements_b == 1024, "matrix B element count mismatch");
    }
}

}  // namespace

int main() {
    Matrix matrix_a{};
    Matrix matrix_b{};
    for (std::size_t row = 0; row < 32U; ++row) {
        for (std::size_t column = 0; column < 32U; ++column) {
            matrix_a[row * 32U + column] = static_cast<std::uint16_t>(
                (row << 8U) | column);
            matrix_b[row * 32U + column] = static_cast<std::uint16_t>(
                0x8000U ^ ((row << 8U) | column));
        }
    }
    const auto expected_a = transpose_matrix(matrix_a);
    const auto expected_b = transpose_matrix(matrix_b);

    test_basic_slice();
    test_command_legality();

    std::cout << "RUN_TEST cmodel_sxm_32x32_single" << '\n';
    const int before_single = failures;
    run_matrix_case(false, matrix_a, matrix_b, expected_a, expected_b);
    if (failures == before_single) {
        std::cout << "CMODEL_SXM_32X32_SINGLE_BLOCK PASS" << '\n';
    }

    std::cout << "RUN_TEST cmodel_sxm_32x32_continuous" << '\n';
    const int before_continuous = failures;
    run_matrix_case(true, matrix_a, matrix_b, expected_a, expected_b);
    if (failures == before_continuous) {
        std::cout << "CMODEL_SXM_32X32_CONTINUOUS PASS" << '\n';
    }
    std::cout << "MATRIX_START_INTERVAL = 4" << '\n';

    if (failures == 0) {
        return 0;
    }
    std::cout << "CMODEL_SXM_SLICE FAIL failures=" << failures << '\n';
    return 1;
}
