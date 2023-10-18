-- SPI Memory Driver
-- Component between the control unit and the onboard flash

-- The implementation is limited on the basic READ command (0x03) shared
-- by a lot of flash chips using SPI and to an address range of 24 bits.
-- This driver could be made more generic to support a wider range of flash chips,
-- but for our purposes this should suffice. 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_memory_driver is
    port (
        clk: in std_ulogic;
        reset: in std_ulogic;

        -- Memory Driver Interface
        address: in std_ulogic_vector(23 downto 0);
        data: out std_ulogic_vector(7 downto 0);

        start: in std_ulogic;
        done: out std_ulogic;

        -- SPI Interface (driven from this entity)
        sclk: out std_ulogic;
        cs_n: out std_ulogic;

        sdi: out std_ulogic;
        sdo: in std_ulogic;

        wp: out std_ulogic;
        hold: out std_ulogic
    );
end entity;

architecture arch of spi_memory_driver is
    type state_t is (STATE_IDLE, STATE_COMMAND, STATE_ADDRESS, STATE_DATA);
    signal state, state_next: state_t;

    signal command, command_next: std_ulogic_vector(7 downto 0);
    signal address_int, address_int_next: std_ulogic_vector(address'range);

    signal data_int, data_int_next: std_ulogic_vector(data'range);

    -- Bits to count: 8 command, 24 address, 8 data
    signal counter, counter_next: unsigned(4 downto 0);

    signal done_int, done_int_next: std_ulogic;

    signal cs_n_int, cs_n_int_next: std_ulogic;

    constant READ_COMMAND: std_ulogic_vector(command'range) := x"03";
begin
    sclk <= clk;
    done <= done_int;
    data <= data_int;

    cs_n <= cs_n_int;

    wp <= '0';
    hold <= '0';

    seq: process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= STATE_IDLE;
                command <= (others => '0');
                address_int <= (others => '0');
                data_int <= (others => '0');
                done_int <= '0';
                counter <= (others => '0');
                cs_n_int <= '1';
            else
                state <= state_next;
                command <= command_next;
                address_int <= address_int_next;
                data_int <= data_int_next;
                done_int <= done_int_next;
                counter <= counter_next;
                cs_n_int <= cs_n_int_next;
            end if;
        end if;
    end process;

    fsm: process (state, command, start, address, address_int, data_int, done_int, counter, sdo, cs_n_int)
    begin
        state_next <= state;
        command_next <= command;
        address_int_next <= address_int;
        data_int_next <= data_int;
        done_int_next <= done_int;
        counter_next <= counter;
        cs_n_int_next <= '1';

        sdi <= '0';

        case state is
            when STATE_IDLE =>
                if start = '1' then
                    state_next <= STATE_COMMAND;

                    command_next <= READ_COMMAND;
                    address_int_next <= address;

                    cs_n_int_next <= '0';

                    counter_next <= (others => '0');
                    done_int_next <= '0';
                end if;

            when STATE_COMMAND =>
                cs_n_int_next <= '0';
                sdi <= command(command'left);
                command_next <= command(command'left-1 downto 0) & '0';
                counter_next <= counter + 1;

                if counter = 7 then
                    state_next <= STATE_ADDRESS;
                    counter_next <= (others => '0');
                end if;

            when STATE_ADDRESS =>
                cs_n_int_next <= '0';
                sdi <= address_int(address_int'left);
                address_int_next <= address_int(address_int'left-1 downto 0) & '0';
                counter_next <= counter + 1;

                if counter = 23 then
                    state_next <= STATE_DATA;
                    counter_next <= (others => '0');
                end if;

            when STATE_DATA =>
                cs_n_int_next <= '0';
                data_int_next <= data_int(data_int'left-1 downto 0) & sdo;
                counter_next <= counter + 1;

                if counter = 7 then
                    state_next <= STATE_IDLE;
                    done_int_next <= '1';
                end if;
        end case;
    end process;
end architecture;
