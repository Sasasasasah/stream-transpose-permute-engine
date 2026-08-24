#include "sxm_permute_engine_model.h"

namespace {

std::uint8_t fixed_source_tile(const std::uint8_t phase,
                               const std::size_t destination_tile) {
    static constexpr std::uint8_t MAP[4][4] = {
        {0U, 3U, 2U, 1U},
        {1U, 0U, 3U, 2U},
        {2U, 1U, 0U, 3U},
        {3U, 2U, 1U, 0U}
    };
    return MAP[phase][destination_tile];
}

}  // namespace

SxmPermuteEngineModel::Outputs
SxmPermuteEngineModel::evaluate(const Inputs& inputs) const {
    Outputs outputs{};
    if (!inputs.cmd_valid) {
        return outputs;
    }

    const bool phase_legal = inputs.phase_id < TILE_ROWS;
    const bool row_legal = inputs.output_row <= 8U;
    const bool tile_legal = inputs.output_tile <= 4U;
    outputs.fault_phase = !phase_legal;
    outputs.fault_selector = !row_legal || !tile_legal;

    if (!phase_legal || !row_legal || !tile_legal) {
        return outputs;
    }

    for (std::size_t destination_tile = 0;
         destination_tile < TILE_ROWS; ++destination_tile) {
        outputs.source_tile_sel[destination_tile] =
            fixed_source_tile(inputs.phase_id, destination_tile);
    }

    for (std::size_t destination_tile = 0;
         destination_tile < TILE_ROWS; ++destination_tile) {
        const std::size_t source_tile =
            outputs.source_tile_sel[destination_tile];
        const bool source_available = inputs.buffer_ready[source_tile] &&
            inputs.buffer_age_ok[source_tile];
        bool destination_active = false;

        if (inputs.output_tile == 4U) {
            destination_active = source_available;
        } else if (inputs.output_tile == destination_tile) {
            destination_active = source_available;
            outputs.fault_buffer_not_ready = !source_available;
        }

        for (std::size_t stream = 0; stream < ACTIVE_STREAMS; ++stream) {
            const bool stream_active = inputs.output_row == 8U ||
                stream == 2U * inputs.output_row ||
                stream == 2U * inputs.output_row + 1U;
            if (destination_active && stream_active) {
                outputs.dst_valid[destination_tile][stream] = true;
                outputs.dst_data[destination_tile][stream] =
                    inputs.buffer_data[source_tile][stream];
            }
        }

        if (destination_active &&
            (inputs.output_row == 7U || inputs.output_row == 8U)) {
            outputs.buffer_release[source_tile] = true;
        }
    }

    return outputs;
}
