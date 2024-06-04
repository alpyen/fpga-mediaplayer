import argparse
import sys
from math import ceil, log2

# Using this script we can calculate three different methods
# of generating a target clock given a faster source clock.

# I've evaluated several methods and just kept one as it is the best out of the three.
# The other methods are still interesting and are elaborated here:
#
# Method 1: Normal Clock Divider
#
#           This is a rather short one, as it is way too imprecise
#           depending on the target frequency.
#
# Method 2: Clock Divider with ratio-based counters
#
#           Instead of the normal clock divider we split the counting interval into two parts.
#           We count two different counters up for a combined total of 2^z (=N) times.
#           Meaning we have counter A that counts x times from 0 to A.
#           And another counter B that counts (N-x) times from 0 to B.
#           This way we have partitioned the counter width from 0..N into 0..x (=x) x..N (=N-x)
#           We can reuse the same counter for A for B aswell since we firstly count
#           x times ceil((src/tgt) / 2), then (N-x) times ceil((src/tgt) / 2 - 1).
#
#           The expression "ceil((src/tgt) / 2)" originated from the original source to target ratio.
#           Since we overshoot with the ceiling function we partition the interval into x times overshoot
#           and the (N-x) times undershoot so we approximate the desired target clock.
#
#           The explanation basically implements this equation:
#               (src/tgt) / 2 = (x*A + (N-x)*B) / N
#
#               A = ceil((src/tgt) / 2), B = ceil((src/tgt) / 2 - 1)
#
#           Note: Since we toggle at the end of each A or B count cycle we have to count half the src/tgt ratio.
#
#           The advantage with this method is that it's very fast to calculate because all values except x are known.
#           And we can scan for different counter withs (z) to explore more precise results.
#
#           The problem with these fixed values is that they can explode when the clock ratios are bad.
#           And we need to spend much much more bits than we would actually need meeting any constraining tolerance.
#
# Method 3: Phase Accumulator
#
#           Since we can only count integers, the phase accumulator will result in
#           almost the same precision as a regular clock divider.
#
#           On top of that it's rather expensive to implement adder being capable
#           of adding sometimes huge increments for such a simple task.

# The method used in this project is a dual clock divider with calculated count values.
#
# It is similar to the second method described but instead of pre-determining the counter values
# to the clock ratio we bruteforce search the entire numeric search space to find the most suitable values.
#
# This method is good because it can optimize the two different counter widths
# to be as minimal as possible while still being within tolerance.
#
# The equation implemented is the same as in Method 2:
#
#   (src/tgt) / 2 = (x*A + (N-x)*B) / N
#
# However this time x, A, B and N are unknown and we need to check all possible values to find the optimal solution.
# I don't know if there's a fancy way like gradient descent to find the global minimum faster, but for the bitwidths
# and tolerances we are working with, it is fine to bruteforce it.
# This only needs to be done once, admittedly I'd rather have this in the VHDL-code as a function but this is faster.
#
# The cost for the entire search space is:
#  N in [1, 2^z], x in [0, Z], A in [0, 2^z], B in [0, 2^z] which is about O(2^(4z)).
#
# Which is just an exponential mess so I don't recommend calculating values over 6 bits.
# 7 bits takes a few minutes to complete already but luckily this method is very accurate and doesn't need many bits.

# Calculates the bits necessary to implement a counter that can count to A or B.
parser = argparse.ArgumentParser(
    prog="clockcalculator",
    description="Calculates the count values to achieve a slower target clock from a source clock.\n",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--source-clock", action="store", type=int, required=True, help="Source clock rate in Hz")
parser.add_argument("-o", "--target-clock", action="store", type=int, required=True, help="Target clock rate in Hz")
parser.add_argument("-b", "--bitwidth", action="store", type=int, required=True, help="Maximum bitwidth of both counters\nWarning: Values above 6 can take a long time to finish!")
parser.add_argument("-s", "--allowed-skew", action="store", type=float, required=True, help="Allowed skew in ms per second")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if int(args.source_clock) <= 0:
    print("Source clock rate has to be a positive integer.")
    exit(0)

if int(args.target_clock) <= 0:
    print("Target clock rate has to be a positive integer.")
    exit(0)

if int(args.source_clock) < int(args.target_clock):
    print("Source clock needs to be faster than the target clock.")
    exit(0)

if int(args.bitwidth) <= 0:
    print("Counter bitwidth needs to be a positive integer.")
    exit(0)

def cost(A: int, B: int) -> int:
    return max(ceil(log2(max(1, A))), ceil(log2(max(1, B))))

source_clock = int(args.source_clock)
target_clock = int(args.target_clock)
source_target_ratio = source_clock / target_clock
half_source_target_ratio = source_target_ratio / 2
allowed_skew_in_ms = float(args.allowed_skew) # 1 / 240 * 30 # 30ms over 4 minutes

bitwidth = int(args.bitwidth)
decimals = 5

print(f"All values cut off to {decimals} decimals.")
print()

print(f"Source Clock: {source_clock} Hz")
print(f"Target Clock: {target_clock} Hz")
print(f"Ratio: {source_target_ratio:.{decimals}f}")
print(f"Toggle: {source_target_ratio / 2:.{decimals}f}")
print(f"Allowed Skew per second: {allowed_skew_in_ms:.{decimals}f} ms ({allowed_skew_in_ms / 1000 * 100:.{decimals}f}%)")
print(f"Allowed Skew per four minutes: {240 * allowed_skew_in_ms:.{decimals}f} ms")
print()

toggle_min_cost = source_clock
cost_min_cost = cost(2 ** bitwidth + 1, 2 ** bitwidth + 1)
skew_min_cost = source_clock
N_min_cost = 0
x_min_cost = 0
A_min_cost = 0
B_min_cost = 0

toggle_min_skew = source_clock
togglediff = abs(toggle_min_cost - half_source_target_ratio)

N_min_skew = 0
x_min_skew = 0
A_min_skew = 0
B_min_skew = 0

print("Exploring search space...", end="")

# The equation is so distributed that we only compute the values
# when they refresh so we don't recalculate them unnecessarily.
for N in range(1, 2 ** bitwidth + 1):
    print("\rExploring search space..." + str(int(N / (2 ** bitwidth + 1) * 100)) + "%", end="", flush=True)

    for x in range(0, N + 1):
        zx = N-x
        xz = x/N

        for A in range(0, 2 ** bitwidth + 1):
            xa = x*A
            xaz = xa/N

            # Ignore the cases where one interval of the clock divider
            # counts to zero elements non zero times.
            # This effectively means that we should simply hang the clock to dry...
            if (A == 0 and x != 0):
                continue

            for B in range(0, 2 ** bitwidth + 1):
                if (B == 0 and zx != 0):
                    continue

                # Precompute some intermediate terms to speed things up
                #toggle = (x*A + (z-x)*B) / z
                toggle = xaz + B-xz*B

                clock_skew = target_clock - (source_clock / (2 * toggle))

                if abs(toggle - half_source_target_ratio) < togglediff:
                    toggle_min_skew = toggle
                    togglediff = abs(toggle - half_source_target_ratio)
                    N_min_skew = N
                    x_min_skew = x
                    A_min_skew = A
                    B_min_skew = B

                new_values_are_cheaper = cost(max(A, B), N) < cost_min_cost and abs(clock_skew / target_clock) * 1000 < allowed_skew_in_ms
                new_values_are_equal_but_better = cost(max(A, B), N) <= cost_min_cost and abs(clock_skew / target_clock) * 1000 < skew_min_cost and abs(clock_skew / target_clock) * 1000 < allowed_skew_in_ms

                if new_values_are_cheaper or new_values_are_equal_but_better:
                    toggle_min_cost = toggle

                    cost_min_cost = cost(max(A, B), N)
                    skew_min_cost = abs(clock_skew / target_clock) * 1000
                    N_min_cost = N
                    x_min_cost = x
                    A_min_cost = A
                    B_min_cost = B

                    achieved_clock2 = source_clock / (2 * toggle_min_cost)
                    clock_skew_min_cost = target_clock - (source_clock / (2 * toggle_min_cost))
                    within_tolerance2 = abs(clock_skew_min_cost / target_clock) * 1000 < allowed_skew_in_ms

                    achieved_clock2best = source_clock / (2 * toggle_min_skew)
                    clock_skew_min_costbest = target_clock - (source_clock / (2 * toggle_min_skew))
                    within_tolerance2best = abs(clock_skew_min_costbest / target_clock) * 1000 < allowed_skew_in_ms


print("\rExploring search space...done!")
print()

achieved_clock2 = source_clock / (2 * toggle_min_cost)
clock_skew_min_cost = target_clock - (source_clock / (2 * toggle_min_cost))
within_tolerance2 = abs(clock_skew_min_cost / target_clock) * 1000 < allowed_skew_in_ms

achieved_clock2best = source_clock / (2 * toggle_min_skew)
clock_skew_min_costbest = target_clock - (source_clock / (2 * toggle_min_skew))
within_tolerance2best = abs(clock_skew_min_costbest / target_clock) * 1000 < allowed_skew_in_ms

print("Minimizing Cost while achieving tolerace:")
print()
print(f"  Achieved: {achieved_clock2:.{decimals}f} Hz")
print(f"  Toggle: {toggle_min_cost:.{decimals}f}")
print(f"  Skew: {clock_skew_min_cost:.{decimals}f} clocks ({(clock_skew_min_cost / target_clock) * 100:.{decimals}f}%)")
print(f"  Skew/second: {(clock_skew_min_cost / target_clock) * 1000:.{decimals}f} ms")
print(f"  Skew/four minutes: {240 * (clock_skew_min_cost / target_clock) * 1000:.{decimals}f} ms")
print(f"  Counter Bitwidths: Z: {cost(N_min_cost, 0)}, A,B: {cost(A_min_cost, B_min_cost)}")
print(f"  x={x_min_cost}, A={A_min_cost}, B={B_min_cost}, N={N_min_cost}")
if not within_tolerance2:
    print()
    print("  Error: Clock is not within tolerance.")
print()
print("Minimizing Skew while within counter bitwidth:")
print()
print(f"  Achieved: {achieved_clock2best:.{decimals}f} Hz")
print(f"  Toggle: {toggle_min_skew:.{decimals}f}")
print(f"  Skew: {clock_skew_min_costbest:.{decimals}f} clocks ({(clock_skew_min_costbest / target_clock) * 100:.{decimals}f}%)")
print(f"  Skew/second: {(clock_skew_min_costbest / target_clock) * 1000:.{decimals}f} ms")
print(f"  Skew/four minutes: {240 * (clock_skew_min_costbest / target_clock) * 1000:.{decimals}f} ms")
print(f"  Z-Counter Bitwidth: {cost(N_min_skew, 0)}, A,B-Counter Bitwidth: {cost(A_min_skew, B_min_skew)}")
print(f"  x={x_min_skew}, A={A_min_skew}, B={B_min_skew}, N={N_min_skew}")
if not within_tolerance2best:
    print()
    print("  Error: Clock is not within tolerance.")
