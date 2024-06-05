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

parser = argparse.ArgumentParser(
    prog="clockcalculator",
    description="Calculates the count values to achieve a slower target clock from a source clock.\n",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--source-clock", action="store", type=int, required=True, help="Source clock rate in Hz")
parser.add_argument("-o", "--target-clock", action="store", type=int, required=True, help="Target clock rate in Hz")
parser.add_argument("-b", "--bitwidth", action="store", type=int, required=True, help="Maximum bitwidth of both counters\nWarning: Values above 6 can take a long time to finish!")
parser.add_argument("-s", "--max-skew", action="store", type=float, required=True, help="Maximum skew in milliseconds per second")
parser.add_argument("-j", "--max-jitter", action="store", type=float, required=True, help="Maximum jitter in percent")
parser.add_argument("-p", "--max-precision", action="store_true", required=False, help="Ignore satisfying solutions if there are more expensive precise ones")
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

if int(args.max_jitter) < 0:
    print("Maximum jitter has to be non-negative integer.")
    exit(0)

# Calculates the bitwidth necessary to implement a counter that can count to A or B.
def cost(A: int, B: int) -> int:
    return max(ceil(log2(max(1, A))), ceil(log2(max(1, B))))

source_clock = int(args.source_clock)
target_clock = int(args.target_clock)
max_skew = float(args.max_skew) # 1 / 240 * 30 # 30ms over 4 minutes
max_jitter = float(args.max_jitter) / 100
max_precision = True if args.max_precision else False
bitwidth = int(args.bitwidth)

source_target_ratio = source_clock / target_clock
half_source_target_ratio = source_target_ratio / 2
max_skew_in_clockcycles = max_skew / 1000 * target_clock

# Cut off values to make it easier to read the console.
decimals = 5

print(f"All values visually cut off to {decimals} decimals.")
print()

print("================== Input Parameters ===================")
print(f"Source Clock:   {source_clock:,} Hz")
print(f"Target Clock:   {target_clock:,} Hz")
print(f"Max. Skew:      {max_skew:.{decimals}f} ms/s")
print(f"Max. Jitter:    {max_jitter:.{decimals}f}%")
print(f"Max. Precision: {max_precision}")
print(f"Max. Bitwidth:  {bitwidth} bits")
print()
print(f"-> Source to Target Ratio: {source_target_ratio:.{decimals}f}")
print(f"-> Toggle Counter Value:   {source_target_ratio / 2:.{decimals}f}")
print(f"-> Max. Skew (4 minutes):  {240 * max_skew:.{decimals}f} ms")
print("=======================================================")
print()

# If we pass all tolerances, the only important optimization goal is the bitwidth which results in more hardware.
# However, just because we found one solution, this does not mean we should stop searching.
# We can still search the current bitwidth for other fractions because their bitwidth cost
# is identical, however they can have lower skew and jitter.
#
# We are interested in the Pareto front so we optimize also for:
#   cost -> skew -> jitter
#   cost -> jitter -> skew
# Looking for the pareto front means that we do not sacrifice gains in
# cost when we found a ratio with less skew. We only update it, if the previous category is not harmed.
#
# If we are interested in max. precision and use the whole bitwidth
# then we update the optimum even if it costs more.
solution_found = False

toggle_min_cost = 0
cost_min_cost = 0
skew_min_cost = 0
jitter_min_cost = 0
N_min_cost = 0
x_min_cost = 0
A_min_cost = 0
B_min_cost = 0

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
            if (A == 0 and x != 0):
                continue

            for B in range(0, 2 ** bitwidth + 1):
                if (B == 0 and zx != 0):
                    continue

                # toggle_current = (x*A + (z-x)*B) / z
                toggle_current = xaz + B-xz*B
                clock_current = source_clock / (2 * toggle_current)
                cost_current = cost(max(A, B), N)
                skew_current = abs(target_clock - clock_current)
                jitter_current = abs(1 - (clock_current / target_clock))

                # In case there exists no solution, we still want to feed some data back to the user.
                # Choose this as a cheap intolerant solution if the skew is lower without loss in jitter,
                # or the jitter is lower without loss in skew.
                # Note that we do not care for the Pareto front as this is just a heads up for the user
                # to see how much they missed their target by and to adjust the parameters.
                cheap_intolerant_solution = (not solution_found) and \
                (
                    (skew_current < skew_min_cost or skew_min_cost == 0) and (jitter_current <= jitter_min_cost or jitter_min_cost == 0) or
                    (skew_current <= skew_min_cost or skew_min_cost == 0) and (jitter_current < jitter_min_cost or jitter_min_cost == 0)
                )

                # compare skew in clockcycles because then we don't have to scale and divide it every iteration
                better_solution_found = (cost_current < cost_min_cost or not solution_found) and (skew_current < max_skew_in_clockcycles) and (jitter_current < max_jitter)
                # new_values_are_cheaper = (cost_current < cost_min_cost or not solution_exists) and (skew_current < max_skew)
                # new_values_are_equal_but_better = (cost_current <= cost_min_cost or not solution_exists) and (skew_current < skew_min_cost) and (skew_current * 1000 < max_skew)

                if better_solution_found:
                    solution_found = True
                    toggle_min_cost = toggle_current
                    cost_min_cost = cost_current
                    skew_min_cost = skew_current
                    jitter_min_cost = jitter_current
                    N_min_cost = N
                    x_min_cost = x
                    A_min_cost = A
                    B_min_cost = B
                elif cheap_intolerant_solution:
                    toggle_min_cost = toggle_current
                    cost_min_cost = cost_current
                    skew_min_cost = skew_current
                    jitter_min_cost = jitter_current
                    N_min_cost = N
                    x_min_cost = x
                    A_min_cost = A
                    B_min_cost = B

    # If we have reached the last possible iteration of the current allowed bitwidth
    # we can exit the search when we have found a solution and are not looking for the
    # most precise solution. Even if we haven't reached bitwidth-bits.
    if not max_precision and solution_found and log2(N) == int(log2(N)):
        break


print("\rExploring search space...done!")
print()

achieved_clock2 = source_clock / (2 * toggle_min_cost)
clock_skew_min_cost = target_clock - (source_clock / (2 * toggle_min_cost))

if solution_found:
    print("================= Cheapest Solution ===================")
else:
    print("ERROR: No solution found that satisfies given constraints.")
    print("       Printing the solution that comes the closest.")
    print()
    print("================== Closest Solution ===================")

print(f"Achieved: {achieved_clock2:.{decimals}f} Hz")
print(f"Toggle: {toggle_min_cost:.{decimals}f}")
print(f"Skew: {clock_skew_min_cost:.{decimals}f} clocks")
print(f"Skew/second: {(clock_skew_min_cost / target_clock) * 1000:.{decimals}f} ms")
print(f"Skew/four minutes: {240 * (clock_skew_min_cost / target_clock) * 1000:.{decimals}f} ms")
print(f"Jitter: {jitter_min_cost*100:.{decimals}f}%")
print(f"Counter Bitwidths: Z: {cost(N_min_cost, 0)}, A,B: {cost(A_min_cost, B_min_cost)}")
print(f"x={x_min_cost}, A={A_min_cost}, B={B_min_cost}, N={N_min_cost}")
print("=======================================================")
