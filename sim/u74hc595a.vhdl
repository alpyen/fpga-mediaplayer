-- Simulation model of the UTC U74HC595A
-- This is a purely functional model, so no timings

library ieee;
use ieee.std_logic_1164.all;

entity u74hc595a is
port (
    srclk: in std_ulogic;
    rclk: in std_ulogic;

    oe_n: in std_ulogic;
    srclr_n: in std_ulogic;

    ser: in std_ulogic;

    q: out std_ulogic_vector(7 downto 0); -- QH downto QA
    qh_buf: out std_ulogic -- QH'
);
end entity;

architecture functional of u74hc595a is
    signal q_buffer, q_buffer_next: std_ulogic_vector(7 downto 0);
    signal q_output, q_output_next: std_ulogic_vector(7 downto 0);
begin
    q_buffer_next <= q_buffer(6 downto 0) & ser;
    q_output_next <= q_buffer;

    q <= q_output when oe_n = '0' else (others => 'Z');
    qh_buf <= q_buffer(7);

    buffer_stage: process (srclk, srclr_n)
    begin
        if srclr_n = '0' then
            q_buffer <= (others => '0');
        elsif rising_edge(srclk) then
            q_buffer <= q_buffer_next;
        end if;
    end process;

    output_stage: process (rclk)
    begin
        if rising_edge(rclk) then
            q_output <= q_output_next;
        end if;
    end process;
end architecture;
