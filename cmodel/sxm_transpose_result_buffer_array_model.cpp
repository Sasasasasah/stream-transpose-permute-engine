#include "sxm_transpose_result_buffer_array_model.h"

void SxmTransposeResultBufferArrayModel::reset() {
    ready_ = {};
    data_ = {};
    dst_meta_ = {};
    input_row_mask_ = {};
    ready_cycle_ = {};
    current_cycle_ = 0;
}

SxmTransposeResultBufferArrayModel::Observation
SxmTransposeResultBufferArrayModel::observe(
    const BoolArray& buffer_release) const {
    Observation observation{};
    observation.buffer_ready = ready_;
    observation.buffer_data = data_;
    observation.buffer_dst_meta = dst_meta_;
    observation.buffer_input_row_mask = input_row_mask_;
    observation.buffer_ready_cycle = ready_cycle_;
    observation.current_cycle = current_cycle_;

    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        observation.buffer_age_ok[tile] =
            ready_[tile] && ready_cycle_[tile] < current_cycle_;
        observation.buffer_available[tile] =
            !ready_[tile] || buffer_release[tile];
    }
    return observation;
}

SxmTransposeResultBufferArrayModel::Observation
SxmTransposeResultBufferArrayModel::step(const Inputs& inputs) {
    // Return cycle-begin OLD state, including availability under this cycle's
    // release intent. Writes commit only after this observation is formed.
    const Observation old_state = observe(inputs.buffer_release);

    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        const bool write_accept = inputs.write_valid[tile] &&
                                  old_state.buffer_available[tile];
        if (write_accept) {
            ready_[tile] = true;
            data_[tile] = inputs.write_data[tile];
            dst_meta_[tile] =
                static_cast<std::uint8_t>(inputs.write_dst_meta[tile] & 0x3FU);
            input_row_mask_[tile] = 0xFFU;
            ready_cycle_[tile] = current_cycle_;
        } else if (inputs.buffer_release[tile]) {
            ready_[tile] = false;
        }
    }

    ++current_cycle_;
    return old_state;
}

std::uint32_t SxmTransposeResultBufferArrayModel::cycle() const {
    return current_cycle_;
}
