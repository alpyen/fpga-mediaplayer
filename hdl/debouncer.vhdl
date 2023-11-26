-- Input Synchronizer and Debouncer
-- synchronizes with a 2-stage flip flop arrangement
-- debounces for a given amount of clock cycles

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.log2;
use ieee.math_real.ceil;

entity debouncer is
    generic (
        COUNT: positive
    );
    port (
        clock: in std_ulogic;

        input: in std_ulogic;
        output: out std_ulogic
    );
end entity;

architecture arch of debouncer is
    signal sync, sync_next: std_ulogic_vector(1 downto 0);
    signal samples, samples_next: std_ulogic_vector(1 downto 0);

    signal counter, counter_next: unsigned(integer(ceil(log2(real(COUNT)))) downto 0);

    signal output_int, output_int_next: std_ulogic;

    constant COUNTER_END: unsigned(counter'range) := to_unsigned(COUNT, counter'length);
begin
    output <= output_int;

    process (sync, samples, counter, output_int, input)
    begin
        sync_next <= sync(0) & input;
        samples_next <= samples(0) & sync(1);
        counter_next <= counter + 1;
        output_int_next <= output_int;

        if samples(1) /= samples(0) then
            counter_next <= to_unsigned(0, counter'length);
        elsif counter >= COUNTER_END then
            output_int_next <= samples(1);
        end if;
    end process;

    process (clock)
    begin
        if rising_edge(clock) then
            sync <= sync_next;
            samples <= samples_next;
            counter <= counter_next;
            output_int <= output_int_next;
        end if;
    end process;
end architecture;
