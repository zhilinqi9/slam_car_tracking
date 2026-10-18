// FW-mini-pro CAN 协议编解码（纯 C++，无 ROS 依赖，可单元测试）
//
// 依据：《FW-mini-pro 用户使用手册 V1.1.1》4.4 / 4.5 节
//   - CAN2.0B 扩展帧，500 kbps，Intel（小端）信号排列
//   - 控制帧周期 10~50 ms，必须带 Alive Rolling Counter（bit52-55）与 BCC 异或校验（Byte7）
//   - Z 轴角速度单位为 0.01 °/s（不是 rad/s），俯视逆时针为正（手册 4.5 例 1）
//
// 本文件只做“字节 <-> 物理量”的转换，不做任何坐标系 / 符号修正；
// 符号与单位的 ROS 化（rad/s、REP-103）在驱动节点里集中处理。
#pragma once

#include <array>
#include <cmath>
#include <cstdint>
#include <limits>

namespace fw_chassis
{
namespace proto
{

using Frame = std::array<uint8_t, 8>;

// 29 位扩展帧 ID（SocketCAN 发送时需再或上 CAN_EFF_FLAG）
constexpr uint32_t kCtrlCmdId = 0x18C4D1D0;
constexpr uint32_t kSteeringCtrlCmdId = 0x18C4D2D0;
constexpr uint32_t kIoCmdId = 0x18C4D7D0;

constexpr uint32_t kCtrlFbId = 0x18C4D1EF;
constexpr uint32_t kSteeringCtrlFbId = 0x18C4D2EF;
constexpr uint32_t kLfWheelFbId = 0x18C4D6EF;
constexpr uint32_t kLrWheelFbId = 0x18C4D7EF;
constexpr uint32_t kRrWheelFbId = 0x18C4D8EF;
constexpr uint32_t kRfWheelFbId = 0x18C4D9EF;
constexpr uint32_t kIoFbId = 0x18C4DAEF;
constexpr uint32_t kFrontAngleFbId = 0x18C4DCEF;
constexpr uint32_t kRearAngleFbId = 0x18C4DDEF;
constexpr uint32_t kBmsFbId = 0x18C4E1EF;
constexpr uint32_t kBmsFlagFbId = 0x18C4E2EF;
constexpr uint32_t kDriveMotorCurrentFbId = 0x18C4E3EF;
constexpr uint32_t kSteeringMotorCurrentFbId = 0x18C4E4EF;
constexpr uint32_t kFrontUltrasonicFbId = 0x18C4E8EF;
constexpr uint32_t kRearUltrasonicFbId = 0x18C4E9EF;
constexpr uint32_t kErrorFbId = 0x18C4EAEF;

// ctrl_cmd 的档位。注意：0 是 disable，不是驻车；驻车是 1。
// steering_ctrl_cmd 使用另一套值（4T4D=5，横移=7），见 SteeringGear。
enum class Gear : uint8_t
{
  kDisable = 0,
  kPark = 1,
  kNeutral = 2,
  k4T4D = 6,     // 仅 vx + wz 有效，vy 被忽略
  kLateral = 8,  // 仅 vx + vy 有效，wz 被忽略
};

enum class SteeringGear : uint8_t
{
  kDisable = 0,
  kPark = 1,
  kNeutral = 2,
  k4T4D = 5,
  kLateral = 7,
};

// ---------- 位操作（Intel / 小端，start_bit 为信号最低位在 64 位整数中的位置） ----------

inline uint64_t toU64(const Frame& d)
{
  uint64_t v = 0;
  for (int i = 7; i >= 0; --i)
    v = (v << 8) | d[i];
  return v;
}

inline uint32_t getBits(const Frame& d, int start_bit, int length)
{
  const uint64_t mask = (length >= 64) ? ~0ull : ((1ull << length) - 1);
  return static_cast<uint32_t>((toU64(d) >> start_bit) & mask);
}

inline int32_t getSigned(const Frame& d, int start_bit, int length)
{
  const uint32_t u = getBits(d, start_bit, length);
  const uint32_t sign = 1u << (length - 1);
  return static_cast<int32_t>((u ^ sign) - sign);  // 补码符号扩展
}

inline void setBits(Frame& d, int start_bit, int length, uint32_t value)
{
  const uint64_t mask = ((1ull << length) - 1) << start_bit;
  uint64_t v = toU64(d);
  v = (v & ~mask) | ((static_cast<uint64_t>(value) << start_bit) & mask);
  for (int i = 0; i < 8; ++i)
    d[i] = static_cast<uint8_t>(v >> (8 * i));
}

inline uint8_t bcc(const Frame& d)
{
  return d[0] ^ d[1] ^ d[2] ^ d[3] ^ d[4] ^ d[5] ^ d[6];
}

inline bool checkBcc(const Frame& d)
{
  return bcc(d) == d[7];
}

// 物理量 -> int16 原始值，四舍五入并饱和（旧驱动直接 float*1000 截断，负数会偏 1 LSB）
inline int16_t toRawInt16(double value, double resolution)
{
  const double r = std::round(value / resolution);
  if (!(r == r))  // NaN
    return 0;
  if (r > std::numeric_limits<int16_t>::max())
    return std::numeric_limits<int16_t>::max();
  if (r < std::numeric_limits<int16_t>::min())
    return std::numeric_limits<int16_t>::min();
  return static_cast<int16_t>(r);
}

inline uint8_t aliveOf(const Frame& d)
{
  return static_cast<uint8_t>(getBits(d, 52, 4));
}

// ---------- 控制帧 ----------

struct CtrlCmd
{
  Gear gear = Gear::kDisable;
  double vx_mps = 0.0;   // 车体 X 线速度，向前为正
  double wz_dps = 0.0;   // 车体 Z 角速度，°/s，俯视逆时针为正
  double vy_mps = 0.0;   // 车体 Y 线速度，向左为正（仅横移档有效）
};

inline Frame encodeCtrlCmd(const CtrlCmd& c, uint8_t alive)
{
  Frame d{};
  setBits(d, 0, 4, static_cast<uint8_t>(c.gear));
  setBits(d, 4, 16, static_cast<uint16_t>(toRawInt16(c.vx_mps, 0.001)));
  setBits(d, 20, 16, static_cast<uint16_t>(toRawInt16(c.wz_dps, 0.01)));
  setBits(d, 36, 16, static_cast<uint16_t>(toRawInt16(c.vy_mps, 0.001)));
  setBits(d, 52, 4, alive & 0x0F);
  d[7] = bcc(d);
  return d;
}

struct SteeringCtrlCmd
{
  SteeringGear gear = SteeringGear::kDisable;
  double velocity_mps = 0.0;  // 虚拟转向轮速度
  double steering_deg = 0.0;  // 虚拟转向轮角度，向左为正
};

inline Frame encodeSteeringCtrlCmd(const SteeringCtrlCmd& c, uint8_t alive)
{
  Frame d{};
  setBits(d, 0, 4, static_cast<uint8_t>(c.gear));
  setBits(d, 4, 16, static_cast<uint16_t>(toRawInt16(c.velocity_mps, 0.001)));
  setBits(d, 20, 16, static_cast<uint16_t>(toRawInt16(c.steering_deg, 0.01)));
  setBits(d, 52, 4, alive & 0x0F);
  d[7] = bcc(d);
  return d;
}

// io_cmd 只开放导航需要的位；其余灯光位保持 0（= 按状态自动控制）
struct IoCmd
{
  bool unlock = false;  // 安全停车解锁，下降沿有效：先发 true 再发 false
};

inline Frame encodeIoCmd(const IoCmd& c, uint8_t alive)
{
  Frame d{};
  setBits(d, 1, 1, c.unlock ? 1 : 0);
  setBits(d, 52, 4, alive & 0x0F);
  d[7] = bcc(d);
  return d;
}

// ---------- 反馈帧（返回 false 表示 BCC 校验失败，调用方应丢弃） ----------

struct CtrlFb
{
  uint8_t gear = 0;
  double vx_mps = 0.0;
  double wz_dps = 0.0;
  double vy_mps = 0.0;
  uint8_t alive = 0;
};

inline bool decodeCtrlFb(const Frame& d, CtrlFb* out)
{
  if (!checkBcc(d))
    return false;
  out->gear = static_cast<uint8_t>(getBits(d, 0, 4));
  out->vx_mps = getSigned(d, 4, 16) * 0.001;
  out->wz_dps = getSigned(d, 20, 16) * 0.01;
  out->vy_mps = getSigned(d, 36, 16) * 0.001;
  out->alive = aliveOf(d);
  return true;
}

struct WheelFb
{
  double velocity_mps = 0.0;
  int32_t pulses = 0;  // 单圈 4096 * 减速比
  uint8_t alive = 0;
};

inline bool decodeWheelFb(const Frame& d, WheelFb* out)
{
  if (!checkBcc(d))
    return false;
  out->velocity_mps = getSigned(d, 0, 16) * 0.001;
  out->pulses = getSigned(d, 16, 32);
  out->alive = aliveOf(d);
  return true;
}

struct IoFb
{
  bool unlock_ok = false;
  uint8_t bumper_bits = 0;     // bit0..5 = 前左/前中/前右/后左/后中/后右防撞条
  bool estop = false;          // 急停开关
  bool remote_control = false; // true = 遥控器控制状态（指令无效）
  bool charging_dock = false;
  bool manual_charger = false;
  bool remote_online = false;
};

inline bool decodeIoFb(const Frame& d, IoFb* out)
{
  if (!checkBcc(d))
    return false;
  out->unlock_ok = getBits(d, 1, 1) != 0;
  out->bumper_bits = static_cast<uint8_t>(getBits(d, 24, 6));
  out->estop = getBits(d, 40, 1) != 0;
  out->remote_control = getBits(d, 41, 1) != 0;
  out->charging_dock = getBits(d, 42, 1) != 0;
  out->manual_charger = getBits(d, 43, 1) != 0;
  out->remote_online = getBits(d, 45, 1) != 0;
  return true;
}

struct BmsFb
{
  double voltage_v = 0.0;
  double current_a = 0.0;
  double remaining_ah = 0.0;
};

inline bool decodeBmsFb(const Frame& d, BmsFb* out)
{
  if (!checkBcc(d))
    return false;
  out->voltage_v = getBits(d, 0, 16) * 0.01;
  out->current_a = getSigned(d, 16, 16) * 0.01;
  out->remaining_ah = getBits(d, 32, 16) * 0.01;
  return true;
}

struct BmsFlagFb
{
  uint8_t soc_percent = 0;
  uint32_t protect_bits = 0;  // Byte1..2 的保护 / 状态位原样保留
  double max_temp_c = 0.0;
  double min_temp_c = 0.0;
};

inline bool decodeBmsFlagFb(const Frame& d, BmsFlagFb* out)
{
  if (!checkBcc(d))
    return false;
  out->soc_percent = static_cast<uint8_t>(getBits(d, 0, 8));
  out->protect_bits = getBits(d, 8, 16);
  out->max_temp_c = getSigned(d, 28, 12) * 0.1;  // 旧驱动未做 12 位符号扩展
  out->min_temp_c = getSigned(d, 40, 12) * 0.1;
  return true;
}

struct ErrorFb
{
  uint8_t level = 0;        // 0 无故障，0xE1/E2/E3 一般/严重/致命
  uint8_t device_type = 0;
  uint8_t device_id = 0;
  uint8_t code = 0;
  uint16_t register_code = 0;
};

inline bool decodeErrorFb(const Frame& d, ErrorFb* out)
{
  if (!checkBcc(d))
    return false;
  out->level = d[0];
  out->device_type = d[1];
  out->device_id = d[2];
  out->code = d[3];
  out->register_code = static_cast<uint16_t>(getBits(d, 32, 16));
  return true;
}

// 超声波：4 个 12 位无符号距离（mm）。200 = 盲区，2540 = 超量程，2560 = 无探头
struct UltrasonicFb
{
  std::array<uint16_t, 4> range_mm{};
};

inline bool decodeUltrasonicFb(const Frame& d, UltrasonicFb* out)
{
  if (!checkBcc(d))
    return false;
  for (int i = 0; i < 4; ++i)
    out->range_mm[i] = static_cast<uint16_t>(getBits(d, 12 * i, 12));
  return true;
}

}  // namespace proto
}  // namespace fw_chassis
