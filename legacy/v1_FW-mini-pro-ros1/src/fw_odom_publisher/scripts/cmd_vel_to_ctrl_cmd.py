#!/usr/bin/env python3
"""
桥接节点:把 move_base 输出的 /cmd_vel (Twist)
转换成 yhs_can_msgs/ctrl_cmd 发到 /ctrl_cmd
适用于全向底盘(支持 vx, vy, vyaw)
"""
import rospy
from geometry_msgs.msg import Twist
from yhs_can_msgs.msg import ctrl_cmd

GEAR_PARK = 0
GEAR_FORWARD = 6 
GEAR_REVERSE = 6

class CmdVelBridge:
    def __init__(self):
        rospy.init_node("cmd_vel_to_ctrl_cmd")

        self.gear_forward = rospy.get_param("~gear_forward", GEAR_FORWARD)
        self.gear_reverse = rospy.get_param("~gear_reverse", GEAR_REVERSE)
        self.gear_park = rospy.get_param("~gear_park", GEAR_PARK)
        self.angular_in_degrees = rospy.get_param("~angular_in_degrees", True)
        self.timeout = rospy.get_param("~timeout", 0.5)

        self.last_msg_time = rospy.Time.now()
        self.last_cmd = None

        self.pub = rospy.Publisher("/ctrl_cmd", ctrl_cmd, queue_size=10)
        rospy.Subscriber("/cmd_vel", Twist, self.cb_cmd_vel, queue_size=10)

        # 用定时器持续发送命令(防止 CAN 控制器超时)
        self.timer = rospy.Timer(rospy.Duration(0.01), self.publish_cmd)

        rospy.loginfo("cmd_vel_to_ctrl_cmd bridge started.")
        rospy.loginfo("  gear_forward=%d, gear_reverse=%d, gear_park=%d",
                      self.gear_forward, self.gear_reverse, self.gear_park)
        rospy.loginfo("  angular_in_degrees=%s", self.angular_in_degrees)

    def cb_cmd_vel(self, msg):
        self.last_msg_time = rospy.Time.now()
        self.last_cmd = msg

    def publish_cmd(self, event):
        out = ctrl_cmd()

        # 命令超时,发停止
        age = (rospy.Time.now() - self.last_msg_time).to_sec()
        if self.last_cmd is None or age > self.timeout:
            out.ctrl_cmd_gear = self.gear_park
            out.ctrl_cmd_x_linear = 0.0
            out.ctrl_cmd_y_linear = 0.0
            out.ctrl_cmd_z_angular = 0.0
            self.pub.publish(out)
            return

        vx = self.last_cmd.linear.x
        vy = self.last_cmd.linear.y
        wz = self.last_cmd.angular.z

        # 决定档位(根据主导线速度方向)
        if abs(vx) < 0.01 and abs(vy) < 0.01 and abs(wz) < 0.01:
            out.ctrl_cmd_gear = self.gear_park
        else:
            out.ctrl_cmd_gear = self.gear_forward    # 你的车前进倒车都是 6

        out.ctrl_cmd_x_linear = vx
        out.ctrl_cmd_y_linear = vy

        # 角速度单位换算
        if self.angular_in_degrees:
            import math
            out.ctrl_cmd_z_angular = math.degrees(wz)
        else:
            out.ctrl_cmd_z_angular = wz

        self.pub.publish(out)


if __name__ == "__main__":
    try:
        CmdVelBridge()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass
