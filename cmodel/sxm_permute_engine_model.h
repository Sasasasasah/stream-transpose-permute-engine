#ifndef SXM_PERMUTE_ENGINE_MODEL_H
#define SXM_PERMUTE_ENGINE_MODEL_H

#include <array>
#include <cstddef>
#include <cstdint>

class SxmPermuteEngineModel {
public:
    static constexpr std::size_t TILE_ROWS = 4;
    static constexpr std::size_t ACTIVE_STREAMS = 16;

    using SegmentArray = std::array<std::uint64_t, ACTIVE_STREAMS>;
    using BufferData = std::array<SegmentArray, TILE_ROWS>;
    using TileBoolArray = std::array<bool, TILE_ROWS>;
    using TileMetaArray = std::array<std::uint8_t, TILE_ROWS>;
    using SourceSelectArray = std::array<std::uint8_t, TILE_ROWS>;
    using DestinationValid =
        std::array<std::array<bool, ACTIVE_STREAMS>, TILE_ROWS>;

    struct Inputs {
        bool cmd_valid = false;
        std::uint8_t phase_id = 0;
        std::uint8_t output_row = 0;
        std::uint8_t output_tile = 0;
        TileBoolArray buffer_ready{};
        TileBoolArray buffer_age_ok{};
        BufferData buffer_data{};
        TileMetaArray buffer_dst_meta{};
    };

    struct Outputs {
        SourceSelectArray source_tile_sel{};
        DestinationValid dst_valid{};
        BufferData dst_data{};
        TileBoolArray buffer_release{};
        bool fault_phase = false;
        bool fault_selector = false;
        bool fault_buffer_not_ready = false;
    };

    Outputs evaluate(const Inputs& inputs) const;
};

#endif
