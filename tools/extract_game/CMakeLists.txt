cmake_minimum_required(VERSION 3.25)
project(crackdown_extract_game LANGUAGES CXX)

find_package(Threads REQUIRED)

get_filename_component(CRACKDOWN_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

add_executable(crackdown_extract_game
    main.cpp
    "${CRACKDOWN_ROOT}/src/game_files.cpp"
    "${CRACKDOWN_ROOT}/src/content_fs.cpp"
    "${CRACKDOWN_ROOT}/src/xdvdfs.cpp"
)
target_include_directories(crackdown_extract_game PRIVATE "${CRACKDOWN_ROOT}/src")
target_compile_features(crackdown_extract_game PRIVATE cxx_std_23)
target_link_libraries(crackdown_extract_game PRIVATE Threads::Threads)
