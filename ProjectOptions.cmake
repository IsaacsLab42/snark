include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(snark_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(snark_setup_options)
  option(snark_ENABLE_HARDENING "Enable hardening" ON)
  option(snark_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    snark_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    snark_ENABLE_HARDENING
    OFF)

  snark_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR snark_PACKAGING_MAINTAINER_MODE)
    option(snark_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(snark_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(snark_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(snark_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(snark_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(snark_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(snark_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(snark_ENABLE_PCH "Enable precompiled headers" OFF)
    option(snark_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(snark_ENABLE_IPO "Enable IPO/LTO" ON)
    option(snark_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(snark_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(snark_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(snark_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(snark_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(snark_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(snark_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(snark_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(snark_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(snark_ENABLE_PCH "Enable precompiled headers" OFF)
    option(snark_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      snark_ENABLE_IPO
      snark_WARNINGS_AS_ERRORS
      snark_ENABLE_USER_LINKER
      snark_ENABLE_SANITIZER_ADDRESS
      snark_ENABLE_SANITIZER_LEAK
      snark_ENABLE_SANITIZER_UNDEFINED
      snark_ENABLE_SANITIZER_THREAD
      snark_ENABLE_SANITIZER_MEMORY
      snark_ENABLE_UNITY_BUILD
      snark_ENABLE_CLANG_TIDY
      snark_ENABLE_CPPCHECK
      snark_ENABLE_COVERAGE
      snark_ENABLE_PCH
      snark_ENABLE_CACHE)
  endif()

  snark_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (snark_ENABLE_SANITIZER_ADDRESS OR snark_ENABLE_SANITIZER_THREAD OR snark_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(snark_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(snark_global_options)
  if(snark_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    snark_enable_ipo()
  endif()

  snark_supports_sanitizers()

  if(snark_ENABLE_HARDENING AND snark_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR snark_ENABLE_SANITIZER_UNDEFINED
       OR snark_ENABLE_SANITIZER_ADDRESS
       OR snark_ENABLE_SANITIZER_THREAD
       OR snark_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${snark_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${snark_ENABLE_SANITIZER_UNDEFINED}")
    snark_enable_hardening(snark_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(snark_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(snark_warnings INTERFACE)
  add_library(snark_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  snark_set_project_warnings(
    snark_warnings
    ${snark_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(snark_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    snark_configure_linker(snark_options)
  endif()

  include(cmake/Sanitizers.cmake)
  snark_enable_sanitizers(
    snark_options
    ${snark_ENABLE_SANITIZER_ADDRESS}
    ${snark_ENABLE_SANITIZER_LEAK}
    ${snark_ENABLE_SANITIZER_UNDEFINED}
    ${snark_ENABLE_SANITIZER_THREAD}
    ${snark_ENABLE_SANITIZER_MEMORY})

  set_target_properties(snark_options PROPERTIES UNITY_BUILD ${snark_ENABLE_UNITY_BUILD})

  if(snark_ENABLE_PCH)
    target_precompile_headers(
      snark_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(snark_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    snark_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(snark_ENABLE_CLANG_TIDY)
    snark_enable_clang_tidy(snark_options ${snark_WARNINGS_AS_ERRORS})
  endif()

  if(snark_ENABLE_CPPCHECK)
    snark_enable_cppcheck(${snark_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(snark_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    snark_enable_coverage(snark_options)
  endif()

  if(snark_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(snark_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(snark_ENABLE_HARDENING AND NOT snark_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR snark_ENABLE_SANITIZER_UNDEFINED
       OR snark_ENABLE_SANITIZER_ADDRESS
       OR snark_ENABLE_SANITIZER_THREAD
       OR snark_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    snark_enable_hardening(snark_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
