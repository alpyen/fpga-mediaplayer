library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_master is
    port (
        i2s_mclk: in std_ulogic;
        i2s_lrck: out std_ulogic;
        i2s_sdata: out std_ulogic
    );
end entity;

architecture arch of i2s_master is
    -- LRCK needs to toggle at 44.1 kHz which is 1/256 of MCLK
    signal lrck_counter, lrck_counter_next: unsigned(7 downto 0) := to_unsigned(0, 8);
    signal left_right_clock, left_right_clock_next: std_ulogic := '0';
begin
    i2s_lrck <= left_right_clock;
    i2s_sdata <= '0';

    seq: process (i2s_mclk)
    begin
        if falling_edge(i2s_mclk) then
            lrck_counter <= lrck_counter_next;
            left_right_clock <= left_right_clock_next;
        end if;
    end process;

    left_right_selection: process (lrck_counter, left_right_clock)
    begin
        lrck_counter_next <= lrck_counter + 1;
        left_right_clock_next <= left_right_clock;

        if lrck_counter = 0 then
            left_right_clock_next <= not left_right_clock;
        end if;
    end process;
end architecture;
