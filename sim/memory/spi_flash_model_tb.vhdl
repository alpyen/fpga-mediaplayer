library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_flash_model_tb is
end entity;

architecture tb of spi_flash_model_tb is
    constant T: time := 10 ns;
    signal sim_done: boolean;

    signal FLASH_SIZE: integer := 256;

    signal sclk: std_ulogic := '0';
    signal cs_n, sdi, sdo: std_ulogic;

    signal data, data_complete: std_ulogic_vector(7 downto 0);
begin
    dut: entity work.spi_flash_model
    generic map (
        SIZE      => FLASH_SIZE, -- 256 B
        INIT_FILE => "../../../../../sim/memory/memory_file.dat",
        INIT_VALUE => x"FF"
    )
    port map (
        sclk => sclk,
        cs_n => cs_n,
        sdi  => sdi,
        sdo  => sdo,
        wp   => 'U',
        hold => 'U'
    );

    clk: process
    begin
        sclk <= not sclk;
        wait for T/2;

        if sim_done then
            wait;
        end if;
    end process;

    test: process
        variable command: std_ulogic_vector(7 downto 0) := std_ulogic_vector(to_unsigned(3, 8));
        variable current_address: std_ulogic_vector(23 downto 0);
    begin
        cs_n <= '1';
        sdi <= '0';

        wait for 2*T;
        
        for address in 0 to FLASH_SIZE / 16 - 1 loop
            current_address := std_ulogic_vector(to_unsigned(address * 16, current_address'length));

            wait until rising_edge(sclk);
            cs_n <= '0';

            for i in command'range loop
                sdi <= command(i);
                wait until rising_edge(sclk);
            end loop;

            for i in current_address'range loop
                sdi <= current_address(i);
                wait until rising_edge(sclk);
            end loop;

            for byteblock in 0 to 15 loop
                for i in data'range loop
                    -- data is shifted out on the falling edge,
                    -- but we have to sample it on the rising edge
                    wait until rising_edge(sclk);
                    data <= data(data'left-1 downto 0) & sdo;
                end loop;

                wait for 0 ns;
                data_complete <= data;
            end loop;

            cs_n <= '1';
            wait for 3*T;
        end loop;

        sim_done <= true;
        wait;
    end process;
end architecture;
