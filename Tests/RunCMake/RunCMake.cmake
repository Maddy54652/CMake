foreach(arg
    RunCMake_GENERATOR
    RunCMake_SOURCE_DIR
    RunCMake_BINARY_DIR
    )
  if(NOT DEFINED ${arg})
    message(FATAL_ERROR "${arg} not given!")
  endif()
endforeach()

function(run_cmake test)
  if(DEFINED ENV{RunCMake_TEST_FILTER} AND NOT test MATCHES "$ENV{RunCMake_TEST_FILTER}")
    return()
  endif()

  set(top_src "${RunCMake_SOURCE_DIR}")
  set(top_bin "${RunCMake_BINARY_DIR}")
  if(EXISTS ${top_src}/${test}-result.txt)
    file(READ ${top_src}/${test}-result.txt expect_result)
    string(REGEX REPLACE "\n+$" "" expect_result "${expect_result}")
  else()
    set(expect_result 0)
  endif()
  foreach(o out err)
    if(RunCMake-std${o}-file AND EXISTS ${top_src}/${RunCMake-std${o}-file})
      file(READ ${top_src}/${RunCMake-std${o}-file} expect_std${o})
      string(REGEX REPLACE "\n+$" "" expect_std${o} "${expect_std${o}}")
    elseif(EXISTS ${top_src}/${test}-std${o}.txt)
      file(READ ${top_src}/${test}-std${o}.txt expect_std${o})
      string(REGEX REPLACE "\n+$" "" expect_std${o} "${expect_std${o}}")
    else()
      unset(expect_std${o})
    endif()
  endforeach()
  if (NOT expect_stderr)
    if (NOT RunCMake_DEFAULT_stderr)
      set(RunCMake_DEFAULT_stderr "^$")
    endif()
    set(expect_stderr ${RunCMake_DEFAULT_stderr})
  endif()

  if (NOT RunCMake_TEST_SOURCE_DIR)
    set(RunCMake_TEST_SOURCE_DIR "${top_src}")
  endif()
  if(NOT RunCMake_TEST_BINARY_DIR)
    set(RunCMake_TEST_BINARY_DIR "${top_bin}/${test}-build")
  endif()
  if(NOT RunCMake_TEST_NO_CLEAN)
    file(REMOVE_RECURSE "${RunCMake_TEST_BINARY_DIR}")
  endif()
  file(MAKE_DIRECTORY "${RunCMake_TEST_BINARY_DIR}")
  if(RunCMake-prep-file AND EXISTS ${top_src}/${RunCMake-prep-file})
    include(${top_src}/${RunCMake-prep-file})
  else()
    include(${top_src}/${test}-prep.cmake OPTIONAL)
  endif()
  if(NOT DEFINED RunCMake_TEST_OPTIONS)
    set(RunCMake_TEST_OPTIONS "")
  endif()
  if(APPLE)
    list(APPEND RunCMake_TEST_OPTIONS -DCMAKE_POLICY_DEFAULT_CMP0025=NEW)
  endif()
  if(RunCMake_MAKE_PROGRAM)
    list(APPEND RunCMake_TEST_OPTIONS "-DCMAKE_MAKE_PROGRAM=${RunCMake_MAKE_PROGRAM}")
  endif()
  if(RunCMake_TEST_OUTPUT_MERGE)
    set(actual_stderr_var actual_stdout)
    set(actual_stderr "")
  else()
    set(actual_stderr_var actual_stderr)
  endif()
  if(DEFINED RunCMake_TEST_TIMEOUT)
    set(maybe_timeout TIMEOUT ${RunCMake_TEST_TIMEOUT})
  else()
    set(maybe_timeout "")
  endif()
  if(RunCMake-stdin-file AND EXISTS ${top_src}/${RunCMake-stdin-file})
    set(maybe_input_file INPUT_FILE ${top_src}/${RunCMake-stdin-file})
  elseif(EXISTS ${top_src}/${test}-stdin.txt)
    set(maybe_input_file INPUT_FILE ${top_src}/${test}-stdin.txt)
  else()
    set(maybe_input_file "")
  endif()
  if(RunCMake_TEST_COMMAND)
    if(NOT RunCMake_TEST_COMMAND_WORKING_DIRECTORY)
      set(RunCMake_TEST_COMMAND_WORKING_DIRECTORY "${RunCMake_TEST_BINARY_DIR}")
    endif()
    execute_process(
      COMMAND ${RunCMake_TEST_COMMAND}
      WORKING_DIRECTORY "${RunCMake_TEST_COMMAND_WORKING_DIRECTORY}"
      OUTPUT_VARIABLE actual_stdout
      ERROR_VARIABLE ${actual_stderr_var}
      RESULT_VARIABLE actual_result
      ENCODING UTF8
      ${maybe_timeout}
      ${maybe_input_file}
      )
  else()
    if(RunCMake_GENERATOR_INSTANCE)
      set(_D_CMAKE_GENERATOR_INSTANCE "-DCMAKE_GENERATOR_INSTANCE=${RunCMake_GENERATOR_INSTANCE}")
    else()
      set(_D_CMAKE_GENERATOR_INSTANCE "")
    endif()
    execute_process(
      COMMAND ${CMAKE_COMMAND} "${RunCMake_TEST_SOURCE_DIR}"
                -G "${RunCMake_GENERATOR}"
                -A "${RunCMake_GENERATOR_PLATFORM}"
                -T "${RunCMake_GENERATOR_TOOLSET}"
                ${_D_CMAKE_GENERATOR_INSTANCE}
                -DRunCMake_TEST=${test}
                --no-warn-unused-cli
                ${RunCMake_TEST_OPTIONS}
      WORKING_DIRECTORY "${RunCMake_TEST_BINARY_DIR}"
      OUTPUT_VARIABLE actual_stdout
      ERROR_VARIABLE ${actual_stderr_var}
      RESULT_VARIABLE actual_result
      ENCODING UTF8
      ${maybe_timeout}
      ${maybe_input_file}
      )
  endif()
  set(msg "")
  if(NOT "${actual_result}" MATCHES "${expect_result}")
    string(APPEND msg "Result is [${actual_result}], not [${expect_result}].\n")
  endif()
  string(CONCAT ignore_line_regex
    "(^|\n)((==[0-9]+=="
    "|BullseyeCoverage"
    "|[a-z]+\\([0-9]+\\) malloc:"
    "|clang[^:]*: warning: the object size sanitizer has no effect at -O0, but is explicitly enabled:"
    "|Error kstat returned"
    "|Hit xcodebuild bug"
    "|[^\n]*xcodebuild[^\n]*warning: file type[^\n]*is based on missing file type"
    "|ld: 0711-224 WARNING: Duplicate symbol: .__init_aix_libgcc_cxa_atexit"
    "|ld: 0711-345 Use the -bloadmap or -bnoquiet option to obtain more information"
    "|[^\n]*is a member of multiple groups"
    "|[^\n]*from Time Machine by path"
    "|[^\n]*Bullseye Testing Technology"
    ")[^\n]*\n)+"
    )
  foreach(o out err)
    string(REGEX REPLACE "\r\n" "\n" actual_std${o} "${actual_std${o}}")
    string(REGEX REPLACE "${ignore_line_regex}" "\\1" actual_std${o} "${actual_std${o}}")
    string(REGEX REPLACE "\n+$" "" actual_std${o} "${actual_std${o}}")
    set(expect_${o} "")
    if(DEFINED expect_std${o})
      if(NOT "${actual_std${o}}" MATCHES "${expect_std${o}}")
        string(REGEX REPLACE "\n" "\n expect-${o}> " expect_${o}
          " expect-${o}> ${expect_std${o}}")
        set(expect_${o} "Expected std${o} to match:\n${expect_${o}}\n")
        string(APPEND msg "std${o} does not match that expected.\n")
      endif()
    endif()
  endforeach()
  unset(RunCMake_TEST_FAILED)
  if(RunCMake-check-file AND EXISTS ${top_src}/${RunCMake-check-file})
    include(${top_src}/${RunCMake-check-file})
  else()
    include(${top_src}/${test}-check.cmake OPTIONAL)
  endif()
  if(RunCMake_TEST_FAILED)
    set(msg "${RunCMake_TEST_FAILED}\n${msg}")
  endif()
  if(msg AND RunCMake_TEST_COMMAND)
    string(REPLACE ";" "\" \"" command "\"${RunCMake_TEST_COMMAND}\"")
    string(APPEND msg "Command was:\n command> ${command}\n")
  endif()
  if(msg)
    string(REGEX REPLACE "\n" "\n actual-out> " actual_out " actual-out> ${actual_stdout}")
    string(REGEX REPLACE "\n" "\n actual-err> " actual_err " actual-err> ${actual_stderr}")
    message(SEND_ERROR "${test} - FAILED:\n"
      "${msg}"
      "${expect_out}"
      "Actual stdout:\n${actual_out}\n"
      "${expect_err}"
      "Actual stderr:\n${actual_err}\n"
      )
  else()
    message(STATUS "${test} - PASSED")
  endif()
endfunction()

function(run_cmake_command test)
  set(RunCMake_TEST_COMMAND "${ARGN}")
  run_cmake(${test})
endfunction()

# Protect RunCMake tests from calling environment.
unset(ENV{MAKEFLAGS})
