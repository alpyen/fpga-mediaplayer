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
parser.add_argument("-d", "--max-sub-clock-deviation", action="store", type=float, required=True, help="Maximum sub clock from target clock deviation in percent")
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

if float(args.max_sub_clock_deviation) < 0:
    print("Maximum deviation has to be non-negative float.")
    exit(0)

source_clock = int(args.source_clock)
target_clock = int(args.target_clock)
max_skew = float(args.max_skew) # 1 / 240 * 30 # 30ms over 4 minutes
max_sub_clock_deviation = float(args.max_sub_clock_deviation) / 100
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
print(f"Source Clock:              {source_clock:,} Hz")
print(f"Target Clock:              {target_clock:,} Hz")
print(f"Max. Skew:                 {max_skew:.{decimals}f} ms/s")
print(f"Max. Sub Clock Deviation:  {max_sub_clock_deviation:.{decimals}f}%")
print(f"Max. Precision:            {max_precision}")
print(f"Max. Bitwidth:             {bitwidth} bits")
print()
print(f"-> Source to Target Ratio: {source_target_ratio:.{decimals}f}")
print(f"-> Toggle Counter Value:   {source_target_ratio / 2:.{decimals}f}")
print(f"-> Max. Skew (4 minutes):  {240 * max_skew:.{decimals}f} ms")
print("=======================================================")
print()

# Calculates the bitwidth necessary to implement a counter that can count to A or B.
def cost(A: int, B: int) -> int:
    return max(ceil(log2(max(1, A))), ceil(log2(max(1, B))))

class Solution:
    def __init__(self, N = 0, x = 0, A = 0, B = 0):
        if N == 0:
            self.toggle = 0
            self.cost = 0
            self.skew = 0
            self.skew_abs = 0
            self.sub_clock_deviation = 0
            self.sub_clock_deviation_abs = 0
            self.N = 0
            self.x = 0
            self.A = 0
            self.B = 0
        else:
            self.toggle = (x*A + (N-x)*B) / N
            self.cost = cost(max(A, B), N)
            clock_current = source_clock / (2 * self.toggle)
            self.skew = target_clock - clock_current
            self.skew_abs = abs(self.skew)
            self.sub_clock_deviation = 1 - (clock_current / target_clock)
            self.sub_clock_deviation_abs = abs(self.sub_clock_deviation)
            self.N = N
            self.x = x
            self.A = A
            self.B = B

    def get_achieved_clock_rate(self):
        return source_clock / (2 * self.toggle)

    def get_toggle_rate(self):
        return self.toggle

    def get_skew_in_clocks(self):
        return self.skew

    def get_skew_in_ms_per_second(self):
        return (self.skew / target_clock) * 1000

    def get_sub_clock_deviation(self):
        return self.sub_clock_deviation

    def get_cost_of_z_counter(self):
        return cost(self.N, 0)

    def get_cost_of_ab_counter(self):
        return cost(self.A, self.B)

    def get_N(self):
        return self.N

    def get_x(self):
        return self.x

    def get_A(self):
        return self.A

    def get_B(self):
        return self.B

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
solution_exists = False

min_cost_solution = Solution()
min_skew_solution = Solution()
min_sub_clock_deviation_solution = Solution()

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
                sub_clock_deviation = abs(1 - (clock_current / target_clock))

                # In case there exists no solution, we still want to feed some data back to the user.
                # Choose this as a cheap intolerant solution if the skew is lower without loss in jitter,
                # or the jitter is lower without loss in skew.
                # Note that we do not care for the Pareto front as this is just a heads up for the user
                # to see how much they missed their target by and to adjust the parameters.
                cheap_intolerant_solution = (not solution_exists) and \
                (
                    (skew_current < min_cost_solution.skew_abs or min_cost_solution.skew_abs == 0)and \
                        (sub_clock_deviation <= min_cost_solution.sub_clock_deviation_abs or min_cost_solution.sub_clock_deviation_abs == 0)
                    or \
                    (skew_current <= min_cost_solution.skew_abs or min_cost_solution.skew_abs == 0) and \
                        (sub_clock_deviation < min_cost_solution.sub_clock_deviation_abs or min_cost_solution.sub_clock_deviation_abs == 0)
                )

                # compare skew in clockcycles because then we don't have to scale and divide it every iteration
                better_solution_found = (cost_current < min_cost_solution.cost or not solution_exists) and (skew_current < max_skew_in_clockcycles) and (sub_clock_deviation < max_sub_clock_deviation)

                if better_solution_found:
                    solution_exists = True

                if better_solution_found or cheap_intolerant_solution:
                    min_cost_solution = Solution(
                        N=N, x=x, A=A, B=B
                    )

    # If we have reached the last possible iteration of the current allowed bitwidth
    # we can exit the search when we have found a solution and are not looking for the
    # most precise solution. Even if we haven't reached bitwidth-bits.
    if not max_precision and solution_exists and log2(N) == int(log2(N)):
        break


print("\rExploring search space...done!")
print()

if solution_exists:
    print("================= Cheapest Solution ===================")
else:
    print("ERROR: No solution found that satisfies given constraints.")
    print("       Printing the solution that comes the closest.")
    print()
    print("================== Closest Solution ===================")

print(f"Achieved:                  {min_cost_solution.get_achieved_clock_rate():,.{decimals}f} Hz")
print(f"Skew/second:               {min_cost_solution.get_skew_in_clocks():.{decimals}f} clocks")
print(f"Skew/second:               {min_cost_solution.get_skew_in_ms_per_second():.{decimals}f} ms")
print(f"Skew/four minutes:         {4 * 60 * min_cost_solution.get_skew_in_ms_per_second():.{decimals}f} ms")
print(f"Sub Clock Deviation:       {min_cost_solution.get_sub_clock_deviation()*100:.{decimals}f}%")
print(f"Toggle:                    {min_cost_solution.get_toggle_rate():.{decimals}f}")
print(f"Bitwidth Counter Z:        {min_cost_solution.get_cost_of_z_counter()}")
print(f"Bitwidth Counter A, B:     {min_cost_solution.get_cost_of_ab_counter()}")
print()
print(f"Values x={min_cost_solution.get_x()}, A={min_cost_solution.get_A()}, B={min_cost_solution.get_B()}, N={min_cost_solution.get_N()}".center(55))
print("=======================================================")
