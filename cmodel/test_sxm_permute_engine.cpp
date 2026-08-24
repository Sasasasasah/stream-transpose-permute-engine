#include "sxm_permute_engine_model.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <initializer_list>
#include <string>

namespace {

using Model = SxmPermuteEngineModel;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

std::uint64_t make_segment(const std::size_t tile,
                           const std::size_t stream) {
    std::uint64_t segment = 0;
    for (std::size_t lane = 0; lane < 8U; ++lane) {
        const auto byte = static_cast<std::uint8_t>(
            tile * 0x43U + stream * 0x0BU + lane * 0x1DU);
        segment |= static_cast<std::uint64_t>(byte) << (lane * 8U);
    }
    return segment;
}

Model::Inputs legal_inputs() {
    Model::Inputs inputs{};
    inputs.cmd_valid = true;
    inputs.output_row = 8U;
    inputs.output_tile = 4U;
    inputs.buffer_ready.fill(true);
    inputs.buffer_age_ok.fill(true);
    for (std::size_t tile = 0; tile < Model::TILE_ROWS; ++tile) {
        inputs.buffer_dst_meta[tile] =
            static_cast<std::uint8_t>(0x10U + tile);
        for (std::size_t stream = 0; stream < Model::ACTIVE_STREAMS;
             ++stream) {
            inputs.buffer_data[tile][stream] = make_segment(tile, stream);
        }
    }
    return inputs;
}

bool no_destination_valid(const Model::Outputs& outputs) {
    for (const auto& tile_valid : outputs.dst_valid) {
        for (const bool valid : tile_valid) {
            if (valid) {
                return false;
            }
        }
    }
    return true;
}

bool no_release(const Model::Outputs& outputs) {
    for (const bool release : outputs.buffer_release) {
        if (release) {
            return false;
        }
    }
    return true;
}

void test_no_command() {
    std::cout << "RUN_TEST no_command" << '\n';
    Model model;
    auto inputs = legal_inputs();
    inputs.cmd_valid = false;
    inputs.buffer_ready.fill(false);
    inputs.buffer_age_ok.fill(false);
    const auto outputs = model.evaluate(inputs);
    expect(no_destination_valid(outputs) && no_release(outputs) &&
               !outputs.fault_phase && !outputs.fault_selector &&
               !outputs.fault_buffer_not_ready,
           "no-command side effect");
}

void test_all_fixed_phases_and_lane_preservation() {
    std::cout << "RUN_TEST fixed_phases_lane_preservation" << '\n';
    static constexpr std::uint8_t EXPECTED[4][4] = {
        {0U, 3U, 2U, 1U},
        {1U, 0U, 3U, 2U},
        {2U, 1U, 0U, 3U},
        {3U, 2U, 1U, 0U}
    };
    Model model;
    for (std::uint8_t phase = 0; phase < 4U; ++phase) {
        auto inputs = legal_inputs();
        inputs.phase_id = phase;
        const auto outputs = model.evaluate(inputs);
        expect(!outputs.fault_phase && !outputs.fault_selector &&
                   !outputs.fault_buffer_not_ready,
               "legal phase fault");
        for (std::size_t destination = 0;
             destination < Model::TILE_ROWS; ++destination) {
            expect(outputs.source_tile_sel[destination] ==
                       EXPECTED[phase][destination],
                   "fixed phase source selection mismatch");
            expect(outputs.buffer_release[
                       EXPECTED[phase][destination]],
                   "ALL row did not release selected source");
            for (std::size_t stream = 0;
                 stream < Model::ACTIVE_STREAMS; ++stream) {
                expect(outputs.dst_valid[destination][stream],
                       "ALL row missing destination valid");
                expect(outputs.dst_data[destination][stream] ==
                           make_segment(EXPECTED[phase][destination], stream),
                       "tile/stream/lane preservation mismatch");
            }
        }
    }
}

void test_row_selectors_and_terminal_release() {
    std::cout << "RUN_TEST row_selectors_terminal_release" << '\n';
    Model model;
    for (std::uint8_t row = 0; row < 8U; ++row) {
        auto inputs = legal_inputs();
        inputs.phase_id = 2U;
        inputs.output_row = row;
        const auto outputs = model.evaluate(inputs);
        for (std::size_t destination = 0;
             destination < Model::TILE_ROWS; ++destination) {
            for (std::size_t stream = 0;
                 stream < Model::ACTIVE_STREAMS; ++stream) {
                const bool expected_valid = stream == 2U * row ||
                                            stream == 2U * row + 1U;
                expect(outputs.dst_valid[destination][stream] ==
                           expected_valid,
                       "row selector valid mismatch");
                if (expected_valid) {
                    const auto source =
                        outputs.source_tile_sel[destination];
                    expect(outputs.dst_data[destination][stream] ==
                               make_segment(source, stream),
                           "row selector data mismatch");
                }
            }
        }
        for (const bool release : outputs.buffer_release) {
            expect(release == (row == 7U),
                   "non-terminal or terminal release mismatch");
        }
    }
}

void test_single_output_tile() {
    std::cout << "RUN_TEST single_output_tile" << '\n';
    Model model;
    auto inputs = legal_inputs();
    inputs.phase_id = 1U;
    inputs.output_tile = 2U;
    const auto outputs = model.evaluate(inputs);
    for (std::size_t destination = 0;
         destination < Model::TILE_ROWS; ++destination) {
        for (std::size_t stream = 0; stream < Model::ACTIVE_STREAMS;
             ++stream) {
            expect(outputs.dst_valid[destination][stream] ==
                       (destination == 2U),
                   "single output tile valid mismatch");
        }
    }
    expect(outputs.source_tile_sel[2] == 3U &&
               outputs.buffer_release ==
                   Model::TileBoolArray{false, false, false, true},
           "single output tile source or release mismatch");
}

void test_buffer_legality_fail_closed() {
    std::cout << "RUN_TEST buffer_legality_fail_closed" << '\n';
    Model model;
    auto inputs = legal_inputs();
    inputs.phase_id = 1U;
    inputs.output_tile = 2U;
    inputs.buffer_ready[3] = false;
    auto outputs = model.evaluate(inputs);
    expect(outputs.fault_buffer_not_ready &&
               no_destination_valid(outputs) && no_release(outputs),
           "not-ready source did not fail closed");

    inputs = legal_inputs();
    inputs.phase_id = 1U;
    inputs.output_tile = 2U;
    inputs.buffer_age_ok[3] = false;
    outputs = model.evaluate(inputs);
    expect(outputs.fault_buffer_not_ready &&
               no_destination_valid(outputs) && no_release(outputs),
           "under-aged source did not fail closed");

}

void test_all_tile_partial_availability() {
    std::cout << "RUN_TEST all_tile_partial_availability" << '\n';
    Model model;

    auto inputs = legal_inputs();
    inputs.phase_id = 0U;
    inputs.buffer_ready = Model::TileBoolArray{true, false, false, false};
    inputs.buffer_age_ok = Model::TileBoolArray{true, false, false, false};
    auto outputs = model.evaluate(inputs);
    expect(!outputs.fault_buffer_not_ready,
           "phase0 partial availability raised a fault");
    expect(outputs.buffer_release ==
               Model::TileBoolArray{true, false, false, false},
           "phase0 partial availability release mismatch");
    for (std::size_t destination = 0;
         destination < Model::TILE_ROWS; ++destination) {
        for (std::size_t stream = 0; stream < Model::ACTIVE_STREAMS;
             ++stream) {
            expect(outputs.dst_valid[destination][stream] ==
                       (destination == 0U),
                   "phase0 partial destination valid mismatch");
        }
    }

    inputs = legal_inputs();
    inputs.phase_id = 1U;
    inputs.buffer_ready = Model::TileBoolArray{true, true, false, false};
    inputs.buffer_age_ok = Model::TileBoolArray{true, true, false, false};
    outputs = model.evaluate(inputs);
    expect(!outputs.fault_buffer_not_ready,
           "phase1 partial availability raised a fault");
    expect(outputs.buffer_release ==
               Model::TileBoolArray{true, true, false, false},
           "phase1 partial availability release mismatch");
    for (std::size_t destination = 0;
         destination < Model::TILE_ROWS; ++destination) {
        for (std::size_t stream = 0; stream < Model::ACTIVE_STREAMS;
             ++stream) {
            const bool expected_active = destination < 2U;
            expect(outputs.dst_valid[destination][stream] == expected_active,
                   "phase1 partial destination valid mismatch");
            if (expected_active) {
                const auto source = destination == 0U ? 1U : 0U;
                expect(outputs.dst_data[destination][stream] ==
                           make_segment(source, stream),
                       "phase1 partial data mismatch");
            }
        }
    }
}

void test_invalid_phase_and_selectors() {
    std::cout << "RUN_TEST invalid_phase_selectors" << '\n';
    Model model;
    for (const std::uint8_t phase : {std::uint8_t{4U},
                                     std::uint8_t{0x80U}}) {
        auto inputs = legal_inputs();
        inputs.phase_id = phase;
        const auto outputs = model.evaluate(inputs);
        expect(outputs.fault_phase && no_destination_valid(outputs) &&
                   no_release(outputs),
               "invalid phase side effect");
    }

    auto inputs = legal_inputs();
    inputs.output_row = 9U;
    auto outputs = model.evaluate(inputs);
    expect(outputs.fault_selector && no_destination_valid(outputs) &&
               no_release(outputs),
           "invalid row selector side effect");

    inputs = legal_inputs();
    inputs.output_tile = 5U;
    outputs = model.evaluate(inputs);
    expect(outputs.fault_selector && no_destination_valid(outputs) &&
               no_release(outputs),
           "invalid tile selector side effect");
}

}  // namespace

int main() {
    test_no_command();
    test_all_fixed_phases_and_lane_preservation();
    test_row_selectors_and_terminal_release();
    test_single_output_tile();
    test_buffer_legality_fail_closed();
    test_all_tile_partial_availability();
    test_invalid_phase_and_selectors();

    if (failures == 0) {
        std::cout << "CMODEL_SXM_PERMUTE_REGRESSION PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_SXM_PERMUTE_REGRESSION FAIL failures="
              << failures << '\n';
    return 1;
}
