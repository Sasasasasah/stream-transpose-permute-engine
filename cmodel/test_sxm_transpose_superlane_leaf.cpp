#include "sxm_transpose_superlane_leaf_model.h"

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>

namespace {

int failures = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << message << '\n';
        ++failures;
    }
}

std::uint8_t get_byte(const std::uint64_t segment,
                      const std::size_t lane) {
    return static_cast<std::uint8_t>((segment >> (lane * 8U)) & 0xFFU);
}

void set_byte(std::uint64_t& segment,
              const std::size_t lane,
              const std::uint8_t value) {
    const std::uint64_t shift = static_cast<std::uint64_t>(lane * 8U);
    const std::uint64_t mask = std::uint64_t{0xFF} << shift;
    segment = (segment & ~mask) |
              (static_cast<std::uint64_t>(value) << shift);
}

SxmTransposeSuperlaneLeafModel::Inputs valid_input() {
    SxmTransposeSuperlaneLeafModel::Inputs inputs{};
    inputs.cmd_valid = true;
    inputs.cmd = {0x01234567U, 0x89ABCDEFU, 0x55AA33CCU};
    inputs.dst_meta = 0x2DU;
    inputs.src_valid = 0xFFFFU;
    inputs.buffer_available = true;
    return inputs;
}

void fill_structured(
    SxmTransposeSuperlaneLeafModel::SegmentArray& segments) {
    for (std::size_t row = 0; row < 8U; ++row) {
        for (std::size_t column = 0; column < 8U; ++column) {
            set_byte(segments[2U * row], column,
                     static_cast<std::uint8_t>(column));
            set_byte(segments[2U * row + 1U], column,
                     static_cast<std::uint8_t>(row));
        }
    }
}

void fill_unique(SxmTransposeSuperlaneLeafModel::SegmentArray& segments) {
    for (std::size_t plane = 0; plane < 2U; ++plane) {
        for (std::size_t row = 0; row < 8U; ++row) {
            for (std::size_t column = 0; column < 8U; ++column) {
                const auto value = static_cast<std::uint8_t>(
                    plane * 128U + row * 8U + column);
                set_byte(segments[2U * row + plane], column, value);
            }
        }
    }
}

void check_structured_result(
    const SxmTransposeSuperlaneLeafModel::SegmentArray& data) {
    for (std::size_t out_row = 0; out_row < 8U; ++out_row) {
        for (std::size_t out_lane = 0; out_lane < 8U; ++out_lane) {
            expect(get_byte(data[2U * out_row], out_lane) == out_row,
                   "structured low-plane transpose mismatch");
            expect(get_byte(data[2U * out_row + 1U], out_lane) == out_lane,
                   "structured high-plane transpose mismatch");
        }
    }
}

void check_unique_result(
    const SxmTransposeSuperlaneLeafModel::SegmentArray& data) {
    for (std::size_t plane = 0; plane < 2U; ++plane) {
        for (std::size_t out_row = 0; out_row < 8U; ++out_row) {
            for (std::size_t out_lane = 0; out_lane < 8U; ++out_lane) {
                const auto expected = static_cast<std::uint8_t>(
                    plane * 128U + out_lane * 8U + out_row);
                expect(get_byte(data[2U * out_row + plane], out_lane) ==
                           expected,
                       "unique transpose byte mismatch");
            }
        }
    }
}

void test_no_command() {
    std::cout << "RUN_TEST no_command" << '\n';
    SxmTransposeSuperlaneLeafModel model;
    model.reset();
    auto inputs = valid_input();
    inputs.cmd_valid = false;
    const auto outputs = model.step(inputs);
    expect(outputs.consume == 0U && !outputs.buffer_write_valid &&
               !outputs.fault_input_invalid && !outputs.fault_buffer_full,
           "no-command side effect");
}

void test_transpose_mapping() {
    std::cout << "RUN_TEST transpose_mapping" << '\n';
    SxmTransposeSuperlaneLeafModel model;
    model.reset();

    auto structured = valid_input();
    fill_structured(structured.src_data);
    const auto structured_outputs = model.step(structured);
    expect(structured_outputs.consume == 0xFFFFU &&
               structured_outputs.buffer_write_valid &&
               structured_outputs.buffer_dst_meta == structured.dst_meta,
           "structured capture control mismatch");
    check_structured_result(structured_outputs.buffer_write_data);

    auto unique = valid_input();
    fill_unique(unique.src_data);
    const auto unique_outputs = model.step(unique);
    check_unique_result(unique_outputs.buffer_write_data);
}

void test_atomicity_and_faults() {
    std::cout << "RUN_TEST valid_consume_fault_atomicity" << '\n';
    SxmTransposeSuperlaneLeafModel model;
    model.reset();

    auto invalid0 = valid_input();
    invalid0.src_valid = 0xFFFEU;
    auto outputs = model.step(invalid0);
    expect(outputs.consume == 0U && !outputs.buffer_write_valid &&
               outputs.fault_input_invalid && !outputs.fault_buffer_full,
           "stream0 invalid behavior");

    auto invalid_mid = valid_input();
    invalid_mid.src_valid = 0xF7FFU;
    outputs = model.step(invalid_mid);
    expect(outputs.consume == 0U && !outputs.buffer_write_valid &&
               outputs.fault_input_invalid,
           "middle-stream invalid behavior");

    auto full = valid_input();
    full.buffer_available = false;
    outputs = model.step(full);
    expect(outputs.consume == 0U && !outputs.buffer_write_valid &&
               !outputs.fault_input_invalid && outputs.fault_buffer_full,
           "buffer-full behavior");

    auto dual = valid_input();
    dual.src_valid = 0xFFDFU;
    dual.buffer_available = false;
    outputs = model.step(dual);
    expect(outputs.consume == 0U && !outputs.buffer_write_valid &&
               outputs.fault_input_invalid && outputs.fault_buffer_full,
           "dual-fault behavior");
}

void test_north_command_pipeline() {
    std::cout << "RUN_TEST north_command_pipeline" << '\n';
    SxmTransposeSuperlaneLeafModel model;
    model.reset();

    auto failed_capture = valid_input();
    failed_capture.cmd = {0xAAAAAAAAU, 0x11112222U, 0xDEADBEEFU};
    failed_capture.dst_meta = 0x15U;
    failed_capture.src_valid = 0xFFFEU;
    failed_capture.buffer_available = false;
    auto outputs = model.step(failed_capture);
    expect(!outputs.north_cmd_valid, "north command advanced without one hop");

    auto idle = valid_input();
    idle.cmd_valid = false;
    outputs = model.step(idle);
    expect(outputs.north_cmd_valid &&
               outputs.north_cmd == failed_capture.cmd &&
               outputs.north_dst_meta == failed_capture.dst_meta,
           "failed capture command or metadata propagation mismatch");

    model.reset();
    auto command_a = valid_input();
    command_a.cmd = {0x0000000AU, 0xAAAA0001U, 0x13579BDFU};
    command_a.dst_meta = 0x0AU;
    auto command_b = valid_input();
    command_b.cmd = {0x0000000BU, 0xBBBB0002U, 0x2468ACE0U};
    command_b.dst_meta = 0x2BU;

    outputs = model.step(command_a);
    expect(!outputs.north_cmd_valid, "back-to-back initial north valid");
    outputs = model.step(command_b);
    expect(outputs.north_cmd_valid && outputs.north_cmd == command_a.cmd &&
               outputs.north_dst_meta == command_a.dst_meta,
           "back-to-back command A metadata mismatch");
    outputs = model.step(idle);
    expect(outputs.north_cmd_valid && outputs.north_cmd == command_b.cmd &&
               outputs.north_dst_meta == command_b.dst_meta,
           "back-to-back command B metadata mismatch");
}

}  // namespace

int main() {
    test_no_command();
    test_transpose_mapping();
    test_atomicity_and_faults();
    test_north_command_pipeline();

    if (failures == 0) {
        std::cout << "CMODEL_SXM_TRANSPOSE_LEAF_REGRESSION PASS" << '\n';
        return 0;
    }
    std::cout << "CMODEL_SXM_TRANSPOSE_LEAF_REGRESSION FAIL failures="
              << failures << '\n';
    return 1;
}
