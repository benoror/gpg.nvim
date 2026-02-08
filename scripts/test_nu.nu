#!/usr/bin/env nu
let script_dir = $env.FILE_PWD
let runner = ($script_dir | path join "run_tests.sh")

^/bin/sh $runner
