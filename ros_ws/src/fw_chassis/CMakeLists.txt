cmake_minimum_required(VERSION 3.0.2)
project(fw_chassis)

add_compile_options(-std=c++14 -Wall -Wextra)

find_package(catkin REQUIRED)

catkin_package(
  INCLUDE_DIRS include
)

include_directories(include)

# 协议层是 header-only；驱动节点（fw_chassis_node）在 P1 阶段加入

install(DIRECTORY include/${PROJECT_NAME}/
  DESTINATION ${CATKIN_PACKAGE_INCLUDE_DESTINATION}
)

if(CATKIN_ENABLE_TESTING)
  catkin_add_gtest(test_protocol test/test_protocol.cpp)
endif()
