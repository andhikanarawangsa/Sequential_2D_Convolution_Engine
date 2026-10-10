#!/usr/bin/env python3
"""Convolution golden model 2D (5x5 * 3x3 -> 3x3) for conv2d_engine verification.

Usage:
  python3 scripts/golden_model.py                       # print Y for test case
  python3 scripts/golden_model.py --check LOG           # compare simulation log (test 1) with golden
  python3 scripts/golden_model.py --random N --seed S   # print N random cases (optional)
"""
import argparse
import random
import re
import sys

X_EXAMPLE = [
    [1, 2, 0, 1, 3],
    [2, 1, 3, 2, 0],
    [0, 1, 2, 1, 1],
    [1, 3, 0, 2, 2],
    [2, 0, 1, 0, 1],
]
K_EXAMPLE = [
    [1, 0, -1],
    [1, 0, -1],
    [1, 0, -1],
]


def conv2d(x, k):
    """Y[i,j] = sum_m sum_n X[i+m, j+n] * K[m, n]  (stride 1, no padding)."""
    y = [[0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            y[i][j] = sum(x[i + m][j + n] * k[m][n] for m in range(3) for n in range(3))
    return y


def show(name, mat):
    print(f"{name} =")
    for row in mat:
        print("  " + " ".join(f"{v:7d}" for v in row))


def check_log(path):
    """Compare the 'RESULT test=1 ...' lines in the simulation log with the golden model."""
    golden = conv2d(X_EXAMPLE, K_EXAMPLE)
    pat = re.compile(r"RESULT test=1 i=(\d) j=(\d) Y=(-?\d+)")
    sim = {}
    with open(path) as f:
        for line in f:
            mo = pat.search(line)
            if mo:
                sim[(int(mo.group(1)), int(mo.group(2)))] = int(mo.group(3))

    print("Y[i,j] | RTL Simulation | Manual/Python | Status")
    print("-------+----------------+---------------+-------")
    ok = True
    for i in range(3):
        for j in range(3):
            s = sim.get((i, j))
            g = golden[i][j]
            good = (s == g)
            ok &= good
            print(f"Y[{i},{j}] | {str(s):>12} | {g:>13} | {'OK' if good else 'MISMATCH'}")
    print("RESULT:", "ALL MATCH" if ok else "SOME MISMATCH")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--check", metavar="LOG", help="simulation log (vvp output) to be compared")
    ap.add_argument("--random", type=int, default=0, metavar="N", help="print N random cases")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    if args.check:
        sys.exit(check_log(args.check))

    show("X", X_EXAMPLE)
    show("K", K_EXAMPLE)
    show("Y", conv2d(X_EXAMPLE, K_EXAMPLE))

    rng = random.Random(args.seed)
    for t in range(args.random):
        x = [[rng.randint(0, 255) for _ in range(5)] for _ in range(5)]
        k = [[rng.randint(-128, 127) for _ in range(3)] for _ in range(3)]
        print(f"\n--- random case #{t + 1} ---")
        show("X", x)
        show("K", k)
        show("Y", conv2d(x, k))


if __name__ == "__main__":
    main()
