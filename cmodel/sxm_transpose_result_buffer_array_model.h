#ifndef SXM_TRANSPOSE_RESULT_BUFFER_ARRAY_MODEL_H
#define SXM_TRANSPOSE_RESULT_BUFFER_ARRAY_MODEL_H

#include <array>
#include <cstddef>
#include <cstdint>

class SxmTransposeResultBufferArrayModel {
public:
    static constexpr std::size_t TILE_ROWS = 4;
    static constexpr std::size_t SEGMENTS_PER_TILE = 16;

    using TileData = std::array<std::uint64_t, SEGMENTS_PER_TILE>;
    using DataArray = std::array<TileData, TILE_ROWS>;
    using BoolArray = std::array<bool, TILE_ROWS>;
    using MetaArray = std::array<std::uint8_t, TILE_ROWS>;
    using MaskArray = std::array<std::uint8_t, TILE_ROWS>;
    using CycleArray = std::array<std::uint32_t, TILE_ROWS>;

    struct Inputs {
        BoolArray write_valid{};
        DataArray write_data{};
        MetaArray write_dst_meta{};
        BoolArray buffer_release{};
    };

    struct Observation {
        BoolArray buffer_ready{};
        BoolArray buffer_age_ok{};
        BoolArray buffer_available{};
        DataArray buffer_data{};
        MetaArray buffer_dst_meta{};
        MaskArray buffer_input_row_mask{};
        CycleArray buffer_ready_cycle{};
        std::uint32_t current_cycle = 0;
    };

    void reset();
    Observation observe(
        const BoolArray& buffer_release = BoolArray{}) const;
    Observation step(const Inputs& inputs);
    std::uint32_t cycle() const;

private:
    BoolArray ready_{};
    DataArray data_{};
    MetaArray dst_meta_{};
    MaskArray input_row_mask_{};
    CycleArray ready_cycle_{};
    std::uint32_t current_cycle_ = 0;
};

#endif
