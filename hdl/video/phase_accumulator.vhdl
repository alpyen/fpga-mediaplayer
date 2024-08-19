library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.round;

entity phase_accumulator is
    generic (
        SOURCE_CLOCK: positive;
        TARGET_CLOCK: positive;
        CLOCK_ACCURACY: real;
        MAX_BITWIDTH: positive;
        MAX_PRECISION: boolean
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        clock_out: out std_ulogic
    );
end entity;

architecture arch of phase_accumulator is
    type solution is record
        exists: boolean;
        achieved: real;
        bitwidth: integer;
        increment: integer;
    end record;

    function clock_calculator (source_clock: positive; target_clock: positive; clock_accuracy: real) return solution is
        variable source: real := real(source_clock);
        variable target: real := real(target_clock);
        variable values: solution;
    begin
        values.exists := false;

        for z in 1 to MAX_BITWIDTH loop
            values.bitwidth := z;
            values.increment := integer(round((target / source) * real(2 ** z)));
            values.achieved := (real(values.increment) / real(2 ** z)) * source;

            if abs(1.0 - (values.achieved / target)) * 100.0 <= clock_accuracy then
                values.exists := true;
                if not MAX_PRECISION then
                    exit;
                end if;
            end if;
        end loop;

        return values;
    end function;

    constant CLOCK_SOLUTION: solution := clock_calculator(SOURCE_CLOCK, TARGET_CLOCK, CLOCK_ACCURACY);
    signal counter: unsigned(CLOCK_SOLUTION.bitwidth-1 downto 0);
begin
    assert CLOCK_SOLUTION.exists = true
    report "phase_accumulator: No solution found that satisfies constraints. Achieved: " & real'image(CLOCK_SOLUTION.achieved) & " Hz " &
           " at Target Deviation: " & real'image(abs(1.0 - (CLOCK_SOLUTION.achieved / real(TARGET_CLOCK))) * 100.0) & "%"
    severity failure;

    process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                counter <= to_unsigned(0, counter'length);
            else
                counter <= counter + CLOCK_SOLUTION.increment;
            end if;
        end if;
    end process;

    clock_out <= counter(counter'left);
end architecture;
