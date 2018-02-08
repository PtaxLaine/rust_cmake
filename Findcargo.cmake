find_package(PythonInterp "3" REQUIRED)
include(FindPackageHandleStandardArgs)

find_program(CARGO_EXECUTABLE cargo)
execute_process(COMMAND ${CARGO_EXECUTABLE} --version
                OUTPUT_VARIABLE CARGO_VERSION
)
string(REGEX REPLACE "cargo +([0-9]+.[0-9]+.[0-9]+).*" "\\1" CARGO_VERSION ${CARGO_VERSION})
find_package_handle_standard_args(cargo
    REQUIRED_VARS CARGO_EXECUTABLE
    VERSION_VAR CARGO_VERSION
)


function(cargo_build_binary source target bin_name bin_path)
    __cargo_parse_argv(4 cmd_args ${ARGV})
    message(STATUS "Build cargo binary `${bin_name}` from ${source}")
    cargo_build_command(${source} ${target} cmd)
    execute_process(
        COMMAND ${cmd} "--bin" ${bin_name} ${cmd_args}
        RESULT_VARIABLE result
        OUTPUT_VARIABLE out
        ERROR_VARIABLE  eout
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
        )
    __cargo_errs_print("${out}")
    if(${result} EQUAL 0)
        __cargo_msg_parse(${out} bin bin)
        set(${bin_path} ${bin} PARENT_SCOPE)
        message(STATUS "${bin}")
        message(STATUS "Build cargo (${source}): successful")
    else()
        message(FATAL_ERROR "Build cargo (${source}): failed! Error code: ${result}\n${eout}")
    endif()
endfunction()


function(cargo_build_staticlib source target lib_path)
    __cargo_parse_argv(3 cmd_args ${ARGV})
    __cargo_build_library(${source} ${target} staticlib lib ${cmd_args})
    set(${lib_path} ${lib} PARENT_SCOPE)
endfunction()


function(cargo_build_cdylib source target lib_path)
    __cargo_parse_argv(3 cmd_args ${ARGV})
    __cargo_build_library(${source} ${target} cdylib lib ${cmd_args})
    set(${lib_path} ${lib} PARENT_SCOPE)
endfunction()


function(__cargo_build_library source target type lib_path)
    __cargo_parse_argv(4 cmd_args ${ARGV})
    message(STATUS "Build cargo ${type} from ${source}")
    cargo_build_command(${source} ${target} cmd)
    execute_process(
        COMMAND ${cmd} "--lib" ${cmd_args}
        RESULT_VARIABLE result
        OUTPUT_VARIABLE out
        ERROR_VARIABLE  eout
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
        )
    __cargo_errs_print("${out}")
    if(${result} EQUAL 0)
        __cargo_msg_parse(${out} ${type} lib)
        set(${lib_path} ${lib} PARENT_SCOPE)
        message(STATUS "${lib}")
        message(STATUS "Build cargo ${type} from (${source}): successful")
    else()
        message(FATAL_ERROR "Build cargo (${source}): failed! Error code: ${result}\n${eout}")
    endif()
endfunction()


macro(__cargo_parse_argv offset result)
    math(EXPR offset "${offset}+2")
    list(LENGTH ARGV argv_len)
    set(cmd_args)
    if(${argv_len} GREATER ${offset})
        math(EXPR stop "${argv_len}-1")
        foreach(i RANGE ${offset} ${stop})
            list(GET ARGV ${i} item)
            list(APPEND cmd_args ${item})
        endforeach()
    endif()
    set(${result} ${cmd_args})
endmacro()


function(__cargo_msg_parse cargo_message type path)
    execute_process(
        COMMAND ${PYTHON_EXECUTABLE} -c ${__pyscript_parse_cargo_msg} ${type} "${cargo_message}"
        OUTPUT_VARIABLE out
        ERROR_VARIABLE  eout
        RESULT_VARIABLE result
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(NOT(${result} EQUAL 0))
        message(FATAL_ERROR "${eout}" "${cargo_message}")
    endif()
    set(${path} ${out} PARENT_SCOPE)
endfunction()


function(__cargo_errs_print cargo_message)
    execute_process(
        COMMAND ${PYTHON_EXECUTABLE} -c ${__pyscript_print_cargo_errs} "${cargo_message}"
    )
endfunction()


function(cargo_build_command source target cmd)
    if(${target} STREQUAL "debug")
        set(target "")
    elseif(${target} STREQUAL "release")
        set(target "--release")
    else()
        message(FATAL_ERROR "Build cargo (${source}): failed! unknow target ${target}")
    endif()

    cargo_command(${source} c_cmd)

    list(APPEND c_cmd build ${target})
    list(APPEND c_cmd --message-format=json)

    set(${cmd} ${c_cmd} PARENT_SCOPE)
endfunction()


function(cargo_command source cmd)
    get_filename_component(CARGO_TARGET ${source} ABSOLUTE)
    get_filename_component(CARGO_TARGET ${CARGO_TARGET} NAME)
    set(CARGO_TARGET ${CMAKE_BINARY_DIR}/cargo-${CARGO_VERSION}/${CARGO_TARGET})
    make_directory( ${CARGO_TARGET} )

    set(c_cmd)
    list(APPEND c_cmd ${CMAKE_COMMAND} -E env CARGO_TARGET_DIR=${CARGO_TARGET})
    list(APPEND c_cmd ${CMAKE_COMMAND} -E chdir ${source})
    list(APPEND c_cmd ${CARGO_EXECUTABLE})

    set(${cmd} ${c_cmd} PARENT_SCOPE)
endfunction()


set(__pyscript_print_cargo_errs "
import sys
import json


def main(messages):
    for msg in messages:
        msg = json.loads(msg)
        if 'message' in msg:
            msg = msg['message']
            if 'message' in msg:
                if 'code' in msg and msg['code']:
                    print('{}:{}'.format(msg['level'], msg['code']['code']))
                else:
                    print('{}'.format(msg['level']))
                print('\t{}'.format(msg['message']))
                if 'spans' in msg:
                    for spans in msg['spans']:
                        print('\t{}:{}:{}'.format(spans['file_name'], spans['line_start'], spans['column_start']))
            

if __name__ == '__main__':
    main(sys.argv[1].split('\\n'))

")

set(__pyscript_parse_cargo_msg "
import os
import sys
import json


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def main(raw_json):
    res = None
    for data in raw_json:
        data = json.loads(data)
        if 'filenames' not in data:
            continue
        if sys.argv[1] == 'staticlib':
            if 'staticlib' in data['target']['crate_types']:
                for x in data['filenames']:
                    ext = os.path.splitext(x)[1]
                    if ext in ('.lib', '.a'):
                        res = x
                        break
        elif sys.argv[1] == 'cdylib':
            if 'cdylib' in data['target']['crate_types']:
                for x in data['filenames']:
                    ext = os.path.splitext(x)[1]
                    if ext in ('.lib', '.a'):
                        res = x
                        break
        elif sys.argv[1] == 'bin':
            if 'bin' in data['target']['crate_types']:
                res = data['filenames'][0]
        else:
            eprint('invalid arguments')
            sys.exit(-1)
    if not res:
        eprint('rust {} detection failed'.format(sys.argv[1]))
        for row in raw_json:
            eprint(json.dumps(json.loads(row), indent=4))
        sys.exit(-1)
    res = os.path.abspath(res)
    assert os.path.exists(res)
    print(res.strip())


if __name__ == '__main__':
    main(sys.argv[2].split('\\n'))

")
