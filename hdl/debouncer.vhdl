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
        clk: in std_ulogic;

        input: in std_ulogic;
        output: out std_ulogic
    );
end entity;

architecture arch of debouncer is
    signal samples, samples_next: std_ulogic_vector(1 downto 0);
    signal counter, counter_next: unsigned(integer(ceil(log2(real(COUNT)))) downto 0);

    signal output_int, output_int_next: std_ulogic;

    constant COUNTER_END: unsigned(counter'range) := to_unsigned(COUNT, counter'length);
begin
    output <= output_int;

    process (samples, counter, input, output_int)
    begin
        counter_next <= counter + 1;
        samples_next <= samples(0) & input;
        output_int_next <= output_int;

        if samples(1) /= samples(0) then
            counter_next <= (others => '0');
        elsif counter >= COUNTER_END then
            output_int_next <= samples(1);
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            samples <= samples_next;
            counter <= counter_next;
            output_int <= output_int_next;
        end if;
    end process;
end architecture;
