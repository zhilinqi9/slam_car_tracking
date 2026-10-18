// 测试向量全部取自《FW-mini-pro 用户使用手册 V1.1.1》4.5 节示例帧。
// 任何对 protocol.hpp 的修改都必须保持这些用例通过。
#include <gtest/gtest.h>

#include "fw_chassis/protocol.hpp"

using namespace fw_chassis::proto;

namespace
{
Frame F(uint8_t a, uint8_t b, uint8_t c, uint8_t d, uint8_t e, uint8_t f, uint8_t g, uint8_t h)
{
  return Frame{ a, b, c, d, e, f, g, h };
}
}  // namespace

// 例 1：4T4D 档，vx = 0.5 m/s，wz = -25 °/s，心跳 1/2/3
TEST(CtrlCmd, Manual4T4DExample)
{
  CtrlCmd c;
  c.gear = Gear::k4T4D;
  c.vx_mps = 0.5;
  c.wz_dps = -25.0;
  EXPECT_EQ(encodeCtrlCmd(c, 1), F(0x46, 0x1F, 0xC0, 0x63, 0x0F, 0x00, 0x10, 0xE5));
  EXPECT_EQ(encodeCtrlCmd(c, 2), F(0x46, 0x1F, 0xC0, 0x63, 0x0F, 0x00, 0x20, 0xD5));
  EXPECT_EQ(encodeCtrlCmd(c, 3), F(0x46, 0x1F, 0xC0, 0x63, 0x0F, 0x00, 0x30, 0xC5));
}

// 例 2：横移档，vx = 0.3 m/s，vy = -0.3 m/s，心跳 4/5/6
TEST(CtrlCmd, ManualLateralExample)
{
  CtrlCmd c;
  c.gear = Gear::kLateral;
  c.vx_mps = 0.3;
  c.vy_mps = -0.3;
  EXPECT_EQ(encodeCtrlCmd(c, 4), F(0xC8, 0x12, 0x00, 0x00, 0x40, 0xED, 0x4F, 0x38));
  EXPECT_EQ(encodeCtrlCmd(c, 5), F(0xC8, 0x12, 0x00, 0x00, 0x40, 0xED, 0x5F, 0x28));
  EXPECT_EQ(encodeCtrlCmd(c, 6), F(0xC8, 0x12, 0x00, 0x00, 0x40, 0xED, 0x6F, 0x18));
}

TEST(CtrlCmd, AliveCounterWrapsAt16)
{
  CtrlCmd c;
  EXPECT_EQ(aliveOf(encodeCtrlCmd(c, 15)), 15);
  EXPECT_EQ(aliveOf(encodeCtrlCmd(c, 16)), 0);
}

TEST(CtrlCmd, SaturatesInsteadOfOverflow)
{
  CtrlCmd c;
  c.gear = Gear::k4T4D;
  c.vx_mps = 100.0;  // 100000 超出 int16
  CtrlFb fb;
  ASSERT_TRUE(decodeCtrlFb(encodeCtrlCmd(c, 0), &fb));
  EXPECT_NEAR(fb.vx_mps, 32.767, 1e-9);
}

// steering_ctrl_cmd 例 1：4T4D(05)，0.3 m/s，-45°
// 注：手册该表格的 ID 列印成了 0x18C4D1D0，按协议表应为 0x18C4D2D0，数据字节不受影响
TEST(SteeringCtrlCmd, Manual4T4DExample)
{
  SteeringCtrlCmd c;
  c.gear = SteeringGear::k4T4D;
  c.velocity_mps = 0.3;
  c.steering_deg = -45.0;
  EXPECT_EQ(encodeSteeringCtrlCmd(c, 1), F(0xC5, 0x12, 0xC0, 0xE6, 0x0E, 0x00, 0x10, 0xEF));
  EXPECT_EQ(encodeSteeringCtrlCmd(c, 3), F(0xC5, 0x12, 0xC0, 0xE6, 0x0E, 0x00, 0x30, 0xCF));
}

// steering_ctrl_cmd 例 2：横移(07)，-0.5 m/s，30°
TEST(SteeringCtrlCmd, ManualLateralExample)
{
  SteeringCtrlCmd c;
  c.gear = SteeringGear::kLateral;
  c.velocity_mps = -0.5;
  c.steering_deg = 30.0;
  EXPECT_EQ(encodeSteeringCtrlCmd(c, 4), F(0xC7, 0xE0, 0x8F, 0xBB, 0x00, 0x00, 0x40, 0x53));
  EXPECT_EQ(encodeSteeringCtrlCmd(c, 6), F(0xC7, 0xE0, 0x8F, 0xBB, 0x00, 0x00, 0x60, 0x73));
}

// io_cmd 解锁例：0x02 ... 心跳 0 / 1
TEST(IoCmd, ManualUnlockExample)
{
  IoCmd c;
  c.unlock = true;
  EXPECT_EQ(encodeIoCmd(c, 0), F(0x02, 0, 0, 0, 0, 0, 0x00, 0x02));
  EXPECT_EQ(encodeIoCmd(c, 1), F(0x02, 0, 0, 0, 0, 0, 0x10, 0x12));
  c.unlock = false;
  EXPECT_EQ(encodeIoCmd(c, 2), F(0x00, 0, 0, 0, 0, 0, 0x20, 0x20));
}

// ctrl_fb 反馈例：与例 1 相同的运动状态，心跳 0xA
TEST(CtrlFb, ManualFeedbackExample)
{
  CtrlFb fb;
  ASSERT_TRUE(decodeCtrlFb(F(0x46, 0x1F, 0xC0, 0x63, 0x0F, 0x00, 0xA0, 0x55), &fb));
  EXPECT_EQ(fb.gear, 6);
  EXPECT_NEAR(fb.vx_mps, 0.5, 1e-9);
  EXPECT_NEAR(fb.wz_dps, -25.0, 1e-9);
  EXPECT_NEAR(fb.vy_mps, 0.0, 1e-9);
  EXPECT_EQ(fb.alive, 0xA);
}

TEST(CtrlFb, ManualLateralFeedbackExample)
{
  CtrlFb fb;
  ASSERT_TRUE(decodeCtrlFb(F(0xC8, 0x12, 0x00, 0x00, 0x40, 0xED, 0xDF, 0xA8), &fb));
  EXPECT_EQ(fb.gear, 8);
  EXPECT_NEAR(fb.vx_mps, 0.3, 1e-9);
  EXPECT_NEAR(fb.vy_mps, -0.3, 1e-9);
}

TEST(CtrlFb, RejectsBadChecksum)
{
  CtrlFb fb;
  EXPECT_FALSE(decodeCtrlFb(F(0x46, 0x1F, 0xC0, 0x63, 0x0F, 0x00, 0xA0, 0x56), &fb));
}

TEST(CtrlCmd, RoundTripThroughFeedbackDecoder)
{
  for (double vx : { -0.8, -0.123, 0.0, 0.001, 0.45 })
    for (double wz : { -90.0, -0.57, 0.0, 12.34, 120.0 })
    {
      CtrlCmd c;
      c.gear = Gear::k4T4D;
      c.vx_mps = vx;
      c.wz_dps = wz;
      CtrlFb fb;
      ASSERT_TRUE(decodeCtrlFb(encodeCtrlCmd(c, 7), &fb));
      EXPECT_NEAR(fb.vx_mps, vx, 0.0005);
      EXPECT_NEAR(fb.wz_dps, wz, 0.005);
    }
}

TEST(WheelFb, SignedVelocityAndPulses)
{
  Frame d{};
  setBits(d, 0, 16, static_cast<uint16_t>(int16_t(-1234)));
  setBits(d, 16, 32, static_cast<uint32_t>(int32_t(-100000)));
  d[7] = bcc(d);
  WheelFb w;
  ASSERT_TRUE(decodeWheelFb(d, &w));
  EXPECT_NEAR(w.velocity_mps, -1.234, 1e-9);
  EXPECT_EQ(w.pulses, -100000);
}

TEST(IoFb, EstopRemoteAndBumpers)
{
  Frame d{};
  setBits(d, 24, 6, 0x05);  // 前左 + 前右防撞条
  setBits(d, 40, 1, 1);     // 急停
  setBits(d, 41, 1, 1);     // 遥控器控制
  d[7] = bcc(d);
  IoFb io;
  ASSERT_TRUE(decodeIoFb(d, &io));
  EXPECT_EQ(io.bumper_bits, 0x05);
  EXPECT_TRUE(io.estop);
  EXPECT_TRUE(io.remote_control);
  EXPECT_FALSE(io.remote_online);
}

TEST(BmsFlagFb, NegativeTemperatureIsSignExtended)
{
  Frame d{};
  setBits(d, 0, 8, 87);
  setBits(d, 28, 12, 0xFFF & static_cast<uint32_t>(int32_t(253)));  // 25.3 ℃
  setBits(d, 40, 12, 0xFFF & static_cast<uint32_t>(int32_t(-52)));  // -5.2 ℃
  d[7] = bcc(d);
  BmsFlagFb b;
  ASSERT_TRUE(decodeBmsFlagFb(d, &b));
  EXPECT_EQ(b.soc_percent, 87);
  EXPECT_NEAR(b.max_temp_c, 25.3, 1e-9);
  EXPECT_NEAR(b.min_temp_c, -5.2, 1e-9);
}

TEST(UltrasonicFb, FourTwelveBitRanges)
{
  Frame d{};
  const uint16_t r[4] = { 200, 2540, 2560, 1234 };
  for (int i = 0; i < 4; ++i)
    setBits(d, 12 * i, 12, r[i]);
  d[7] = bcc(d);
  UltrasonicFb u;
  ASSERT_TRUE(decodeUltrasonicFb(d, &u));
  for (int i = 0; i < 4; ++i)
    EXPECT_EQ(u.range_mm[i], r[i]);
}

int main(int argc, char** argv)
{
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
