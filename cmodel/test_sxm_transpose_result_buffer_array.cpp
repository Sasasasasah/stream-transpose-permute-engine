#include "sxm_transpose_result_buffer_array_model.h"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

using Model = SxmTransposeResultBufferArrayModel;

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

Model::TileData make_data(const std::uint64_t seed) {
    Model::TileData data{};
    for (std::size_t segment = 0; segment < data.size(); ++segment) {
        data[segment] = seed + static_cast<std::uint64_t>(segment);
    }
    return data;
}

void test_reset_write_age_and_full_protection() {
    std::cout << "RUN_TEST reset_write_age_full_protection" << '\n';
    Model model;
    model.reset();

    auto observation = model.observe();
    for (std::size_t tile = 0; tile < Model::TILE_ROWS; ++tile) {
        expect(!observation.buffer_ready[tile] &&
                   !observation.buffer_age_ok[tile] &&
                   observation.buffer_available[tile],
               "reset state mismatch");
    }

    const auto data_a = make_data(0x1000U);
    Model::Inputs write_a{};
    write_a.write_valid[0] = true;
    write_a.write_data[0] = data_a;
    write_a.write_dst_meta[0] = 0x11U;
    const auto write_cycle = model.step(write_a);
    expect(!write_cycle.buffer_ready[0] &&
               !write_cycle.buffer_age_ok[0] &&
               write_cycle.buffer_available[0],
           "write cycle did not expose old empty state");

    observation = model.observe();
    expect(observation.buffer_ready[0] &&
               observation.buffer_age_ok[0] &&
               observation.buffer_data[0] == data_a &&
               observation.buffer_dst_meta[0] == 0x11U &&
               observation.buffer_input_row_mask[0] == 0xFFU &&
               observation.buffer_ready_cycle[0] == 0U &&
               observation.current_cycle == 1U,
           "basic write or next-cycle age mismatch");

    const auto data_b = make_data(0x2000U);
    Model::Inputs illegal_write{};
    illegal_write.write_valid[0] = true;
    illegal_write.write_data[0] = data_b;
    illegal_write.write_dst_meta[0] = 0x22U;
    const auto full_cycle = model.step(illegal_write);
    expect(!full_cycle.buffer_available[0] &&
               full_cycle.buffer_data[0] == data_a,
           "full entry advertised available or changed early");
    observation = model.observe();
    expect(observation.buffer_data[0] == data_a &&
               observation.buffer_dst_meta[0] == 0x11U &&
               observation.buffer_ready_cycle[0] == 0U,
           "illegal write overwrote full buffer");
}

void test_release_and_same_cycle_reuse() {
    std::cout << "RUN_TEST release_and_same_cycle_reuse" << '\n';
    Model model;
    model.reset();
    const auto data_a = make_data(0x3000U);
    const auto data_b = make_data(0x4000U);

    Model::Inputs seed{};
    seed.write_valid[0] = true;
    seed.write_data[0] = data_a;
    seed.write_dst_meta[0] = 0x13U;
    model.step(seed);

    Model::Inputs reuse{};
    reuse.buffer_release[0] = true;
    reuse.write_valid[0] = true;
    reuse.write_data[0] = data_b;
    reuse.write_dst_meta[0] = 0x24U;
    const auto old_state = model.step(reuse);
    expect(old_state.buffer_ready[0] && old_state.buffer_age_ok[0] &&
               old_state.buffer_available[0] &&
               old_state.buffer_data[0] == data_a &&
               old_state.buffer_dst_meta[0] == 0x13U,
           "reuse cycle did not expose OLD buffer");

    auto observation = model.observe();
    expect(observation.buffer_ready[0] &&
               observation.buffer_age_ok[0] &&
               observation.buffer_data[0] == data_b &&
               observation.buffer_dst_meta[0] == 0x24U &&
               observation.buffer_ready_cycle[0] == 1U,
           "reuse did not commit NEW buffer for next cycle");

    Model::Inputs release_only{};
    release_only.buffer_release[0] = true;
    const auto release_state = model.step(release_only);
    expect(release_state.buffer_ready[0] &&
               release_state.buffer_available[0] &&
               release_state.buffer_data[0] == data_b,
           "release cycle lost OLD observation");
    observation = model.observe();
    expect(!observation.buffer_ready[0] &&
               !observation.buffer_age_ok[0] &&
               observation.buffer_available[0],
           "release-only next state mismatch");
}

void test_four_tile_independence_and_metadata() {
    std::cout << "RUN_TEST four_tile_independence_metadata" << '\n';
    Model model;
    model.reset();

    const auto old0 = make_data(0x5000U);
    const auto old1 = make_data(0x6000U);
    const auto old2 = make_data(0x7000U);
    const auto new0 = make_data(0x8000U);
    const auto new3 = make_data(0x9000U);

    Model::Inputs seed{};
    for (std::size_t tile = 0; tile < 3U; ++tile) {
        seed.write_valid[tile] = true;
    }
    seed.write_data[0] = old0;
    seed.write_data[1] = old1;
    seed.write_data[2] = old2;
    seed.write_dst_meta = {0x01U, 0x12U, 0x23U, 0x00U};
    model.step(seed);

    Model::Inputs mixed{};
    mixed.buffer_release[0] = true;
    mixed.write_valid[0] = true;
    mixed.write_data[0] = new0;
    mixed.write_dst_meta[0] = 0x34U;
    mixed.buffer_release[2] = true;
    mixed.write_valid[3] = true;
    mixed.write_data[3] = new3;
    mixed.write_dst_meta[3] = 0x3DU;
    const auto old_state = model.step(mixed);
    expect(old_state.buffer_available ==
               Model::BoolArray{true, false, true, true},
           "mixed-operation availability mismatch");

    const auto observation = model.observe();
    expect(observation.buffer_ready ==
               Model::BoolArray{true, true, false, true},
           "mixed-operation ready independence mismatch");
    expect(observation.buffer_data[0] == new0 &&
               observation.buffer_dst_meta[0] == 0x34U &&
               observation.buffer_data[1] == old1 &&
               observation.buffer_dst_meta[1] == 0x12U &&
               observation.buffer_data[2] == old2 &&
               observation.buffer_data[3] == new3 &&
               observation.buffer_dst_meta[3] == 0x3DU,
           "four-tile data or metadata independence mismatch");
}

void test_repeated_reuse_and_ready_cycles() {
    std::cout << "RUN_TEST repeated_reuse_ready_cycles" << '\n';
    Model model;
    model.reset();

    for (std::size_t tile = 0; tile < Model::TILE_ROWS; ++tile) {
        Model::Inputs write{};
        write.write_valid[tile] = true;
        write.write_data[tile] = make_data(0xA000U + tile * 0x100U);
        write.write_dst_meta[tile] =
            static_cast<std::uint8_t>(0x08U + tile);
        model.step(write);
    }
    auto observation = model.observe();
    expect(observation.buffer_ready_cycle ==
               Model::CycleArray{0U, 1U, 2U, 3U},
           "per-tile ready_cycle mismatch");

    for (std::uint32_t generation = 0; generation < 3U; ++generation) {
        Model::Inputs reuse{};
        reuse.buffer_release[0] = true;
        reuse.write_valid[0] = true;
        reuse.write_data[0] = make_data(0xB000U + generation * 0x100U);
        reuse.write_dst_meta[0] =
            static_cast<std::uint8_t>(0x20U + generation);
        const auto old_state = model.step(reuse);
        expect(old_state.buffer_ready[0] &&
                   old_state.buffer_available[0] &&
                   old_state.buffer_age_ok[0],
               "repeated reuse old-state mismatch");
        observation = model.observe();
        expect(observation.buffer_ready[0] &&
                   observation.buffer_age_ok[0] &&
                   observation.buffer_dst_meta[0] ==
                       static_cast<std::uint8_t>(0x20U + generation),
               "repeated reuse new-state mismatch");
    }
}

}  // namespace

int main() {
    test_reset_write_age_and_full_protection();
    test_release_and_same_cycle_reuse();
    test_four_tile_independence_and_metadata();
    test_repeated_reuse_and_ready_cycles();

    if (failures == 0) {
        std::cout << "CMODEL_SXM_RESULT_BUFFER_REGRESSION PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_SXM_RESULT_BUFFER_REGRESSION FAIL failures="
              << failures << '\n';
    return 1;
}
