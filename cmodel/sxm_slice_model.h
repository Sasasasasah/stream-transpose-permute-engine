#ifndef SXM_SLICE_MODEL_H
#define SXM_SLICE_MODEL_H

#include "sxm_permute_engine_model.h"
#include "sxm_transpose_result_buffer_array_model.h"

#include <array>
#include <cstddef>
#include <cstdint>

class SxmSliceModel {
public:
    static constexpr std::size_t TILE_ROWS = 4;
    static constexpr std::size_t ACTIVE_STREAMS = 16;

    using Command = std::array<std::uint32_t, 3>;
    using SegmentArray = std::array<std::uint64_t, ACTIVE_STREAMS>;
    using TileData = std::array<SegmentArray, TILE_ROWS>;
    using TileMask = std::array<std::uint16_t, TILE_ROWS>;
    using TileBool = std::array<bool, TILE_ROWS>;
    using SelectorArray =
        std::array<std::array<std::uint8_t, ACTIVE_STREAMS>, TILE_ROWS>;
    using WriteValid =
        std::array<std::array<bool, ACTIVE_STREAMS>, TILE_ROWS>;

    struct DecodedCommand {
        std::uint8_t opcode = 0;
        bool src_direction = false;
        std::uint8_t src_base = 0;
        bool dst_direction = false;
        std::uint8_t dst_base = 0;
        std::uint8_t input_row = 0;
        std::uint8_t output_row = 0;
        std::uint8_t output_tile = 0;
        std::uint8_t phase_id = 0;
        bool reserved_nonzero = false;
    };

    struct Inputs {
        bool transpose_cmd_valid = false;
        Command transpose_cmd{};
        bool permute_cmd_valid = false;
        Command permute_cmd{};
        TileMask sr_read_valid{};
        TileData sr_read_data{};
    };

    struct Observation {
        std::uint64_t cycle = 0;
        SelectorArray read_selector{};
        TileMask consume{};
        WriteValid write_valid{};
        std::array<std::uint8_t, ACTIVE_STREAMS> write_selector{};
        TileData write_data{};

        TileBool stage_valid{};
        TileBool stage_src_direction{};
        std::array<std::uint8_t, TILE_ROWS> stage_src_base{};

        TileBool buffer_ready{};
        TileBool buffer_age_ok{};
        std::array<std::uint32_t, TILE_ROWS> buffer_ready_cycle{};
        TileData buffer_data{};
        std::array<std::uint8_t, TILE_ROWS> buffer_dst_meta{};

        TileBool transpose_input_invalid{};
        TileBool transpose_buffer_full{};
        bool permute_phase_fault = false;
        bool permute_selector_fault = false;
        bool permute_buffer_not_ready = false;
        bool fault_valid = false;
        bool busy = false;
    };

    void reset();
    Observation step(const Inputs& inputs);
    SelectorArray read_selectors(bool transpose_cmd_valid,
                                 const Command& transpose_cmd) const;
    SxmTransposeResultBufferArrayModel::Observation buffer_state() const;
    std::uint64_t cycle() const;

    // CURRENT DRAFT SXM ENTRY DECODE. FINAL ISA NOT FROZEN.
    static DecodedCommand decode_command(const Command& command);

private:
    TileBool stage_valid_q_{};
    std::array<Command, TILE_ROWS> stage_command_q_{};
    SxmTransposeResultBufferArrayModel result_buffers_;
    SxmPermuteEngineModel permute_engine_;
    std::uint64_t cycle_ = 0;
};

#endif
