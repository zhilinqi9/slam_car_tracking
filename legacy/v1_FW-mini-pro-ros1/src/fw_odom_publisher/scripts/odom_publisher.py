#!/usr/bin/env python3
"""
订阅 /ctrl_fb (yhs_can_msgs/ctrl_fb) -> 发布 /odom (nav_msgs/Odometry) + tf

输入: x_linear (m/s), z_angular (假设 rad/s)
输出: 位置 (x, y) + 朝向 (theta)
"""
import math
import rospy
import tf2_ros
from nav_msgs.msg import Odometry
from geometry_msgs.msg import Quaternion, TransformStamped
from yhs_can_msgs.msg import ctrl_fb


class FwOdomPublisher:
    def __init__(self):
        rospy.init_node("fw_odom_publisher")

        # 参数(可在 launch 文件覆盖)
        self.odom_frame = rospy.get_param("~odom_frame", "odom")
        self.base_frame = rospy.get_param("~base_frame", "base_link")
        # /ctrl_fb 角速度单位假设是 rad/s,如果实测发现不对改成 True 自动转换
        self.angular_in_degrees = rospy.get_param("~angular_in_degrees", False)
        # 是否发布 tf
        self.publish_tf = rospy.get_param("~publish_tf", True)

        # 状态
        self.x = 0.0
        self.y = 0.0
        self.theta = 0.0
        self.last_time = None

        # 发布器
        self.odom_pub = rospy.Publisher("/odom", Odometry, queue_size=50)
        self.tf_broadcaster = tf2_ros.TransformBroadcaster()

        # 订阅器
        rospy.Subscriber("/ctrl_fb", ctrl_fb, self.cb_ctrl_fb, queue_size=50)

        rospy.loginfo("fw_odom_publisher started.")
        rospy.loginfo("  odom_frame=%s, base_frame=%s", self.odom_frame, self.base_frame)
        rospy.loginfo("  angular_in_degrees=%s, publish_tf=%s",
                      self.angular_in_degrees, self.publish_tf)

    def cb_ctrl_fb(self, msg):
        now = rospy.Time.now()

        # 第一帧只记录时间,不积分
        if self.last_time is None:
            self.last_time = now
            return

        dt = (now - self.last_time).to_sec()
        self.last_time = now

        # 异常 dt 跳过(节点刚启动可能跳一个 0)
        if dt <= 0.0 or dt > 1.0:
            return

        v = msg.ctrl_fb_x_linear  # m/s
        w = msg.ctrl_fb_z_angular  # rad/s 或 度/s
        if self.angular_in_degrees:
            w = math.radians(w)

        # 积分位姿(用更稳定的中点法)
        delta_theta = w * dt
        avg_theta = self.theta + delta_theta / 2.0

        self.x += v * math.cos(avg_theta) * dt
        self.y += v * math.sin(avg_theta) * dt
        self.theta += delta_theta

        # 角度归一到 [-pi, pi]
        self.theta = math.atan2(math.sin(self.theta), math.cos(self.theta))

        # 构造四元数(只绕 z 轴)
        q = Quaternion()
        q.x = 0.0
        q.y = 0.0
        q.z = math.sin(self.theta / 2.0)
        q.w = math.cos(self.theta / 2.0)

        # 发布 /odom
        odom = Odometry()
        odom.header.stamp = now - rospy.Duration(0.005)
        odom.header.frame_id = self.odom_frame
        odom.child_frame_id = self.base_frame
        odom.pose.pose.position.x = self.x
        odom.pose.pose.position.y = self.y
        odom.pose.pose.position.z = 0.0
        odom.pose.pose.orientation = q
        odom.twist.twist.linear.x = v
        odom.twist.twist.linear.y = 0.0
        odom.twist.twist.angular.z = w

        # 简单协方差(对角线,差不多就行)
        odom.pose.covariance[0] = 0.01   # x
        odom.pose.covariance[7] = 0.01   # y
        odom.pose.covariance[14] = 1e6   # z (二维不用)
        odom.pose.covariance[21] = 1e6   # roll
        odom.pose.covariance[28] = 1e6   # pitch
        odom.pose.covariance[35] = 0.05  # yaw
        odom.twist.covariance[0] = 0.01
        odom.twist.covariance[7] = 1e6
        odom.twist.covariance[14] = 1e6
        odom.twist.covariance[21] = 1e6
        odom.twist.covariance[28] = 1e6
        odom.twist.covariance[35] = 0.05

        self.odom_pub.publish(odom)

        # 发布 tf: odom -> base_link
        if self.publish_tf:
            tf_msg = TransformStamped()
            tf_msg.header.stamp = now - rospy.Duration(0.005)
            tf_msg.header.frame_id = self.odom_frame
            tf_msg.child_frame_id = self.base_frame
            tf_msg.transform.translation.x = self.x
            tf_msg.transform.translation.y = self.y
            tf_msg.transform.translation.z = 0.0
            tf_msg.transform.rotation = q
            self.tf_broadcaster.sendTransform(tf_msg)


if __name__ == "__main__":
    try:
        FwOdomPublisher()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass
