#ifndef SXM_TRANSPOSE_SUPERLANE_LEAF_MODEL_H
#define SXM_TRANSPOSE_SUPERLANE_LEAF_MODEL_H

#include <array>
#include <cstdint>

class SxmTransposeSuperlaneLeafModel {
public:
    static constexpr std::size_t STREAMS = 16;
    static constexpr std::size_t LANES = 8;
    static constexpr std::size_t PLANES = 2;

    using Command = std::array<std::uint32_t, 3>;
    using SegmentArray = std::array<std::uint64_t, STREAMS>;

    struct Inputs {
        bool cmd_valid = false;
        Command cmd{};
        std::uint8_t dst_meta = 0;
        std::uint16_t src_valid = 0;
        SegmentArray src_data{};
        bool buffer_available = false;
    };

    struct Outputs {
        std::uint16_t consume = 0;
        bool buffer_write_valid = false;
        SegmentArray buffer_write_data{};
        std::uint8_t buffer_dst_meta = 0;
        bool fault_input_invalid = false;
        bool fault_buffer_full = false;
        bool north_cmd_valid = false;
        Command north_cmd{};
        std::uint8_t north_dst_meta = 0;
    };

    void reset();
    Outputs step(const Inputs& inputs);
    std::uint64_t cycle() const;

private:
    bool north_cmd_valid_ = false;
    Command north_cmd_{};
    std::uint8_t north_dst_meta_ = 0;
    std::uint64_t cycle_ = 0;
};

#endif
