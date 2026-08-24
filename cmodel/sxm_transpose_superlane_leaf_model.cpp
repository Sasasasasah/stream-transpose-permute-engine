#include "sxm_transpose_superlane_leaf_model.h"

namespace {

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

}  // namespace

void SxmTransposeSuperlaneLeafModel::reset() {
    north_cmd_valid_ = false;
    north_cmd_ = {};
    north_dst_meta_ = 0;
    cycle_ = 0;
}

SxmTransposeSuperlaneLeafModel::Outputs
SxmTransposeSuperlaneLeafModel::step(const Inputs& inputs) {
    Outputs outputs{};

    // North outputs expose the command held at cycle start. The current input
    // command becomes visible through the north hop on the next step.
    outputs.north_cmd_valid = north_cmd_valid_;
    outputs.north_cmd = north_cmd_;
    outputs.north_dst_meta = north_dst_meta_;

    const bool all_src_valid = inputs.src_valid == 0xFFFFU;
    const bool capture_success = inputs.cmd_valid && all_src_valid &&
                                 inputs.buffer_available;

    outputs.consume = capture_success ? 0xFFFFU : 0U;
    outputs.buffer_write_valid = capture_success;
    outputs.buffer_dst_meta = static_cast<std::uint8_t>(inputs.dst_meta & 0x3FU);
    outputs.fault_input_invalid = inputs.cmd_valid && !all_src_valid;
    outputs.fault_buffer_full = inputs.cmd_valid && !inputs.buffer_available;

    // Output segment index is 2*out_row+plane. Byte out_lane comes from
    // input segment 2*out_lane+plane at byte out_row.
    for (std::size_t out_row = 0; out_row < LANES; ++out_row) {
        for (std::size_t plane = 0; plane < PLANES; ++plane) {
            const std::size_t output_segment = 2U * out_row + plane;
            for (std::size_t out_lane = 0; out_lane < LANES; ++out_lane) {
                const std::size_t input_segment = 2U * out_lane + plane;
                set_byte(outputs.buffer_write_data[output_segment], out_lane,
                         get_byte(inputs.src_data[input_segment], out_row));
            }
        }
    }

    north_cmd_valid_ = inputs.cmd_valid;
    north_cmd_ = inputs.cmd;
    north_dst_meta_ = static_cast<std::uint8_t>(inputs.dst_meta & 0x3FU);
    ++cycle_;
    return outputs;
}

std::uint64_t SxmTransposeSuperlaneLeafModel::cycle() const {
    return cycle_;
}
