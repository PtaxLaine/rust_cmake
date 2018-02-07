include(FindPackageHandleStandardArgs)

find_program(RUSTC_EXECUTABLE rustc)
execute_process(COMMAND ${RUSTC_EXECUTABLE} --version
			    OUTPUT_VARIABLE RUSTC_VERSION
)

string(REGEX REPLACE "rustc +([0-9]+.[0-9]+.[0-9]+).*" "\\1" RUSTC_VERSION ${RUSTC_VERSION})

find_package_handle_standard_args(rustc
	REQUIRED_VARS RUSTC_EXECUTABLE
	VERSION_VAR RUSTC_VERSION
)
