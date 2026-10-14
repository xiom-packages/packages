# XIOM -- regenerate the generated-consts region of ktx2.xi.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Splices the `tools/oracle_ktx.py emit-consts` output (ktx.h + KHR/khr_df.h
# enums and the ktx.h numeric macros, resolved to Int32) between the two
# marker comments in ktx2.xi. Run after any vendor re-pin and check the
# diff.
#
# Usage: python tools/sync_consts.py <module.xi>

import os
import subprocess
import sys

BEGIN = "// >>> GENERATED CONSTS (tools/oracle_ktx.py emit-consts) -- do not edit by hand"
END = "// <<< GENERATED CONSTS"

HERE = os.path.dirname(os.path.abspath(__file__))


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    module_path = argv[1]
    out = subprocess.check_output(
        [sys.executable, os.path.join(HERE, "oracle_ktx.py"), "emit-consts"],
        text=True)
    with open(module_path, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    b = text.find(BEGIN)
    e = text.find(END)
    if b < 0 or e < 0 or e < b:
        sys.stderr.write("markers not found in %s\n" % module_path)
        return 1
    head = text[:b + len(BEGIN)] + "\n"
    tail = text[e:]
    with open(module_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(head + out + tail)
    print("consts spliced: %d lines" % (out.count("\n") + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
