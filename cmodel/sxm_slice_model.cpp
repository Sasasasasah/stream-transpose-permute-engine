#include "sxm_slice_model.h"

namespace {

std::uint8_t get_byte(const std::uint64_t segment,
                      const std::size_t lane) {
    return static_cast<std::uint8_t>((segment >> (lane * 8U)) & 0xFFU);
}

void set_byte(std::uint64_t& segment, const std::size_t lane,
              const std::uint8_t value) {
    const auto shift = static_cast<std::uint64_t>(lane * 8U);
    const auto mask = std::uint64_t{0xFFU} << shift;
    segment = (segment & ~mask) |
        (static_cast<std::uint64_t>(value) << shift);
}

SxmSliceModel::SegmentArray transpose_segments(
    const SxmSliceModel::SegmentArray& input) {
    SxmSliceModel::SegmentArray output{};
    for (std::size_t out_row = 0; out_row < 8U; ++out_row) {
        for (std::size_t plane = 0; plane < 2U; ++plane) {
            const std::size_t output_stream = 2U * out_row + plane;
            for (std::size_t out_lane = 0; out_lane < 8U; ++out_lane) {
                const std::size_t input_stream = 2U * out_lane + plane;
                set_byte(output[output_stream], out_lane,
                         get_byte(input[input_stream], out_row));
            }
        }
    }
    return output;
}

}  // namespace

void SxmSliceModel::reset() {
    stage_valid_q_ = {};
    stage_command_q_ = {};
    result_buffers_.reset();
    cycle_ = 0;
}

SxmSliceModel::DecodedCommand
SxmSliceModel::decode_command(const Command& command) {
    // CURRENT DRAFT SXM ENTRY DECODE. FINAL ISA NOT FROZEN.
    const std::uint64_t low = static_cast<std::uint64_t>(command[0]) |
        (static_cast<std::uint64_t>(command[1]) << 32U);
    DecodedCommand decoded{};
    decoded.opcode = static_cast<std::uint8_t>(low & 0x3U);
    decoded.src_direction = ((low >> 2U) & 0x1U) != 0U;
    decoded.src_base = static_cast<std::uint8_t>((low >> 3U) & 0x1FU);
    decoded.dst_direction = ((low >> 8U) & 0x1U) != 0U;
    decoded.dst_base = static_cast<std::uint8_t>((low >> 9U) & 0x1FU);
    decoded.input_row = static_cast<std::uint8_t>((low >> 14U) & 0xFU);
    decoded.output_row = static_cast<std::uint8_t>((low >> 18U) & 0xFU);
    decoded.output_tile = static_cast<std::uint8_t>((low >> 22U) & 0x7U);
    decoded.phase_id = static_cast<std::uint8_t>((low >> 25U) & 0xFFU);
    decoded.reserved_nonzero = (command[1] & 0xFFFFFFFEU) != 0U ||
        command[2] != 0U;
    return decoded;
}

SxmSliceModel::SelectorArray SxmSliceModel::read_selectors(
    const bool transpose_cmd_valid, const Command& transpose_cmd) const {
    SelectorArray selectors{};
    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        const Command& command = tile == 0U ? transpose_cmd :
            stage_command_q_[tile];
        const auto decoded = decode_command(command);
        const bool external_legal = decoded.opcode == 0U &&
            decoded.src_base <= 16U && decoded.dst_base <= 16U &&
            decoded.input_row == 8U && !decoded.reserved_nonzero;
        const bool valid = tile == 0U ?
            (transpose_cmd_valid && external_legal) :
            stage_valid_q_[tile];
        if (valid && decoded.src_base <= 16U) {
            for (std::size_t stream = 0; stream < ACTIVE_STREAMS; ++stream) {
                selectors[tile][stream] = static_cast<std::uint8_t>(
                    (decoded.src_direction ? 0x20U : 0U) |
                    (decoded.src_base + stream));
            }
        }
    }
    return selectors;
}

SxmSliceModel::Observation SxmSliceModel::step(const Inputs& inputs) {
    Observation outputs{};
    outputs.cycle = cycle_;

    const auto external_transpose = decode_command(inputs.transpose_cmd);
    const auto external_permute = decode_command(inputs.permute_cmd);
    const bool transpose_legal = external_transpose.opcode == 0U &&
        external_transpose.src_base <= 16U &&
        external_transpose.dst_base <= 16U &&
        external_transpose.input_row == 8U &&
        !external_transpose.reserved_nonzero;
    const bool permute_legal = external_permute.opcode == 1U &&
        external_permute.src_base <= 16U &&
        external_permute.dst_base <= 16U &&
        !external_permute.reserved_nonzero;
    const bool effective_transpose_valid = inputs.transpose_cmd_valid &&
        transpose_legal;
    const bool effective_permute_valid = inputs.permute_cmd_valid &&
        permute_legal;
    const bool command_invalid =
        (inputs.transpose_cmd_valid && !transpose_legal) ||
        (inputs.permute_cmd_valid && !permute_legal);

    std::array<Command, TILE_ROWS> current_commands{};
    current_commands[0] = inputs.transpose_cmd;
    outputs.stage_valid[0] = effective_transpose_valid;
    for (std::size_t tile = 1; tile < TILE_ROWS; ++tile) {
        current_commands[tile] = stage_command_q_[tile];
        outputs.stage_valid[tile] = stage_valid_q_[tile];
    }

    outputs.read_selector = read_selectors(effective_transpose_valid,
                                           inputs.transpose_cmd);
    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        const auto decoded = decode_command(current_commands[tile]);
        outputs.stage_src_direction[tile] = decoded.src_direction;
        outputs.stage_src_base[tile] = decoded.src_base;
    }

    // Permute is combinational and sees only cycle-begin OLD buffer state.
    const auto old_buffers = result_buffers_.observe();
    SxmPermuteEngineModel::Inputs permute_inputs{};
    const auto permute_command = external_permute;
    permute_inputs.cmd_valid = effective_permute_valid;
    permute_inputs.phase_id = permute_command.phase_id;
    permute_inputs.output_row = permute_command.output_row;
    permute_inputs.output_tile = permute_command.output_tile;
    permute_inputs.buffer_ready = old_buffers.buffer_ready;
    permute_inputs.buffer_age_ok = old_buffers.buffer_age_ok;
    permute_inputs.buffer_data = old_buffers.buffer_data;
    permute_inputs.buffer_dst_meta = old_buffers.buffer_dst_meta;
    const auto permute_outputs = permute_engine_.evaluate(permute_inputs);

    outputs.write_valid = permute_outputs.dst_valid;
    outputs.write_data = permute_outputs.dst_data;
    outputs.permute_phase_fault = permute_outputs.fault_phase;
    outputs.permute_selector_fault = permute_outputs.fault_selector;
    outputs.permute_buffer_not_ready =
        permute_outputs.fault_buffer_not_ready;
    if (effective_permute_valid) {
        for (std::size_t stream = 0; stream < ACTIVE_STREAMS; ++stream) {
            outputs.write_selector[stream] = static_cast<std::uint8_t>(
                (permute_command.dst_direction ? 0x20U : 0U) |
                (permute_command.dst_base + stream));
        }
    }

    const auto available_buffers =
        result_buffers_.observe(permute_outputs.buffer_release);
    SxmTransposeResultBufferArrayModel::Inputs buffer_inputs{};
    buffer_inputs.buffer_release = permute_outputs.buffer_release;

    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        const bool all_valid = inputs.sr_read_valid[tile] == 0xFFFFU;
        const bool capture = outputs.stage_valid[tile] && all_valid &&
            available_buffers.buffer_available[tile];
        outputs.consume[tile] = capture ? 0xFFFFU : 0U;
        outputs.transpose_input_invalid[tile] =
            outputs.stage_valid[tile] && !all_valid;
        outputs.transpose_buffer_full[tile] =
            outputs.stage_valid[tile] &&
            !available_buffers.buffer_available[tile];

        const auto decoded = decode_command(current_commands[tile]);
        buffer_inputs.write_valid[tile] = capture;
        buffer_inputs.write_data[tile] =
            transpose_segments(inputs.sr_read_data[tile]);
        buffer_inputs.write_dst_meta[tile] = static_cast<std::uint8_t>(
            (decoded.dst_direction ? 0x20U : 0U) | decoded.dst_base);
    }

    outputs.buffer_ready = old_buffers.buffer_ready;
    outputs.buffer_age_ok = old_buffers.buffer_age_ok;
    outputs.buffer_ready_cycle = old_buffers.buffer_ready_cycle;
    outputs.buffer_data = old_buffers.buffer_data;
    outputs.buffer_dst_meta = old_buffers.buffer_dst_meta;
    outputs.busy = false;
    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        outputs.fault_valid = outputs.fault_valid ||
            outputs.transpose_input_invalid[tile] ||
            outputs.transpose_buffer_full[tile];
        outputs.busy = outputs.busy || outputs.stage_valid[tile] ||
            old_buffers.buffer_ready[tile];
    }
    outputs.fault_valid = outputs.fault_valid ||
        outputs.permute_phase_fault || outputs.permute_selector_fault ||
        outputs.permute_buffer_not_ready || command_invalid;

    // Commit release/write atomically, then advance the command pipeline.
    // Accepted write priority implements read-old/release-old/write-new.
    result_buffers_.step(buffer_inputs);
    for (std::size_t tile = TILE_ROWS - 1U; tile > 1U; --tile) {
        stage_valid_q_[tile] = stage_valid_q_[tile - 1U];
        stage_command_q_[tile] = stage_command_q_[tile - 1U];
    }
    stage_valid_q_[1] = effective_transpose_valid;
    stage_command_q_[1] = inputs.transpose_cmd;
    ++cycle_;
    return outputs;
}

SxmTransposeResultBufferArrayModel::Observation
SxmSliceModel::buffer_state() const {
    return result_buffers_.observe();
}

std::uint64_t SxmSliceModel::cycle() const {
    return cycle_;
}
