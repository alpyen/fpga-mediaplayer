-- Functional model of the onboard SPI flash (Macronix / Spansion)
-- This model only supports the basic READ command
-- For faster simulation try using smaller flash sizes

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity spi_flash_model is
generic (
    SIZE: positive;
    INIT_FILE: string;
    INIT_VALUE: std_ulogic_vector(7 downto 0)
);
port (
    sclk: in std_ulogic;
    cs_n: in std_ulogic;

    sdi: inout std_ulogic;
    sdo: inout std_ulogic;

    wp_n: inout std_ulogic;
    hold_n: inout std_ulogic;

    tb_memory: out std_ulogic_vector(SIZE * 8 - 1 downto 0)
);
end entity;

architecture functional of spi_flash_model is
    type memory_t is array (0 to SIZE-1) of std_ulogic_vector(7 downto 0);
    signal memory: memory_t := (others => INIT_VALUE);

    type state_t is (STATE_COMMAND, STATE_ADDRESS, STATE_DATA);
    signal state, state_next: state_t;

    signal command, command_next: std_ulogic_vector(7 downto 0);
    signal address, address_next: std_ulogic_vector(23 downto 0);
    signal data, data_next: std_ulogic_vector(7 downto 0);

    signal data_out, data_out_next: std_ulogic_vector(7 downto 0);

    signal counter, counter_next: integer;

    constant READ_COMMAND: std_ulogic_vector(command'range) := std_ulogic_vector(to_unsigned(3, command'length));

    procedure info (message: in string) is
    begin
        report "spi_flash_model: " & message severity note;
    end procedure;

    procedure assert_fail (condition: in boolean; message: in string) is
    begin
        assert condition report "spi_flash_model: " & message severity failure;
    end procedure;
begin
    init: process
        procedure load_file is
            function byte_to_std_ulogic_vector (byte: in string(1 to 2)) return std_ulogic_vector is
                variable sulv: std_ulogic_vector(7 downto 0);
                variable nibble: integer;
            begin
                for i in 1 to 2 loop
                    case byte(i) is
                        when '0' => nibble := 0;
                        when '1' => nibble := 1;
                        when '2' => nibble := 2;
                        when '3' => nibble := 3;
                        when '4' => nibble := 4;
                        when '5' => nibble := 5;
                        when '6' => nibble := 6;
                        when '7' => nibble := 7;
                        when '8' => nibble := 8;
                        when '9' => nibble := 9;
                        when 'A' => nibble := 10;
                        when 'B' => nibble := 11;
                        when 'C' => nibble := 12;
                        when 'D' => nibble := 13;
                        when 'E' => nibble := 14;
                        when 'F' => nibble := 15;
                        when others => assert_fail(false, "Bad byte read: " & byte(i+1));
                    end case;

                    sulv(4*(2-i)+3 downto 4*(2-i)+0) := std_ulogic_vector(to_unsigned(nibble, 4));
                end loop;

                return sulv;
            end function;

            file memory_file: text;
            variable fos: file_open_status;

            variable current_line: line;
            variable current_address: integer := 0;
            
            variable byte: string(1 to 2);
            variable space: character;

            variable good: boolean;
        begin
            info("Loading init file: """ & INIT_FILE & """.");

            file_open(fos, memory_file, INIT_FILE, read_mode);
            assert_fail(fos = open_ok, "Loading init file failed: " & file_open_status'image(fos) & ".");

            while not endfile(memory_file) loop
                readline(memory_file, current_line);

                while current_line'length > 0 loop
                    assert_fail(
                        current_address < SIZE,
                        "Init file is bigger than flash size. Aborting!"
                    );
                    
                    read(current_line, byte, good);
                    assert_fail(good, "Reading bad byte at: " & integer'image(current_address) & ".");

                    if current_line'length /= 0 then
                        read(current_line, space, good);
                        assert_fail(
                            good and (space = ' ' or space = cr),
                            "Reading bad byte at: " & integer'image(current_address) & "."
                        );
                    end if;

                    memory(current_address) <= byte_to_std_ulogic_vector(byte);
                    current_address := current_address + 1;
                end loop;
            end loop;

            info("Flash initialized with " & integer'image(current_address) & " bytes from init file.");
        end procedure;
    begin
        info("Initializing flash with size of " & integer'image(SIZE) & " bytes.");

        if INIT_FILE'length /= 0 then
            load_file;
        end if;

        wait;
    end process;

    process (memory)
    begin
        for i in memory'range loop
            tb_memory(i*8+7 downto i*8) <= memory(i);
        end loop;
    end process;

    sdo <= data_out(7);

    seq: process (sclk, cs_n)
    begin
        if cs_n = '1' then
            state <= STATE_COMMAND;
            counter <= 0;
            data <= (others => 'Z');
            data_out <= (others => 'Z');
        -- sdi is latched in on the rising edge of the clock
        elsif rising_edge(sclk) then
            state <= state_next;
            counter <= counter_next;
            command <= command_next;
            address <= address_next;
            data <= data_next;
        -- sdo is shifted out on the falling edge of the clock
        elsif falling_edge(sclk)then
            data_out <= data_out_next;
        end if;
    end process;

    fsm: process (state, counter, command, address, data, data_out, state_next, counter_next, command_next, address_next)
    begin
        state_next <= state;
        counter_next <= counter;
        command_next <= command;
        address_next <= address;
        data_next <= data;
        data_out_next <= data_out;

        case state is
            when STATE_COMMAND =>
                command_next <= command(command'left-1 downto 0) & sdi;
                counter_next <= counter + 1;

                if counter = command'length - 1 then
                    state_next <= STATE_ADDRESS;
                    counter_next <= 0;

                    assert_fail(
                        (state_next = STATE_ADDRESS and command_next = READ_COMMAND) or state_next = state,
                        "Invalid Command: " & integer'image(to_integer(unsigned(command_next)))
                    );
                end if;

            when STATE_ADDRESS =>
                address_next <= address(address'left-1 downto 0) & sdi;
                counter_next <= counter + 1;

                if counter = address'length - 1 then
                    state_next <= STATE_DATA;
                    counter_next <= 0;

                    -- wait one delta cycle so address_next is correct
                    -- this has to be done otherwise the address might point
                    -- to a location that does not exist
                    if state_next = STATE_DATA then
                        data_next <= memory(to_integer(unsigned(address_next)));
                    end if;

                    assert_fail(
                        (state_next = STATE_DATA and unsigned(address_next) < SIZE) or state_next = state,
                        "Invalid Address: " & integer'image(to_integer(unsigned(address_next)))
                    );
                end if;

            when STATE_DATA =>
                data_next <= data(data'left-1 downto 0) & 'Z';
                data_out_next <= data;
                counter_next <= counter + 1;

                if counter = data'length - 1 then
                    -- Increase to the next address and/or wrap around the address range
                    address_next <= std_ulogic_vector(to_unsigned(to_integer((unsigned(address) + 1)) mod SIZE, address_next'length));
                    counter_next <= 0;

                    if counter_next = 0 then
                        data_next <= memory(to_integer(unsigned(address_next)));
                    end if;
                end if;
        end case;
    end process;
end architecture;
