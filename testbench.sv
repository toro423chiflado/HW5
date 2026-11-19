`timescale 1ns/1ps

module testbench;

    localparam integer SELECT_CASE = 0;
    localparam integer STEP_LIMIT = 200;

    logic clk = 0;
    logic step = 0;
    logic [31:0] pc;
    logic halted;
    logic error;

    riscv32_sim dut (
        .clk(clk),
        .step(step),
        .pc(pc),
        .halted(halted),
        .error(error)
    );

    wire [31:0] debug_x1 = dut.regs[1];
    wire [31:0] debug_x2 = dut.regs[2];
    wire [31:0] debug_x3 = dut.regs[3];
    wire [31:0] debug_x5 = dut.regs[5];
    wire [31:0] debug_a0 = dut.regs[10];

    function automatic logic [31:0] encode_r(
        input integer f7,
        input integer rs2,
        input integer rs1,
        input integer f3,
        input integer rd
    );
        encode_r = {f7[6:0], rs2[4:0], rs1[4:0], f3[2:0], rd[4:0], 7'h33};
    endfunction

    function automatic logic [31:0] encode_i(
        input integer imm,
        input integer rs1,
        input integer f3,
        input integer rd,
        input integer opcode
    );
        encode_i = {imm[11:0], rs1[4:0], f3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic logic [31:0] encode_s(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input integer f3
    );
        encode_s = {imm[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] encode_b(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input integer f3
    );
        encode_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:1], imm[11], 7'h63};
    endfunction

    function automatic logic [31:0] encode_u(
        input integer imm,
        input integer rd,
        input integer opcode
    );
        encode_u = {imm[31:12], rd[4:0], opcode[6:0]};
    endfunction

    function automatic logic [31:0] encode_j(
        input integer imm,
        input integer rd
    );
        encode_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], 7'h6f};
    endfunction

    task automatic emit(input integer fd, input logic [31:0] instruction);
        $fwrite(fd, "%c%c%c%c", instruction[7:0], instruction[15:8], instruction[23:16], instruction[31:24]);
    endtask

    task automatic create_arithmetic();
        integer fd;
        fd = $fopen("arithmetic.bin", "wb");
        if (fd == 0) $fatal(1, "No se pudo crear arithmetic.bin");
        emit(fd, encode_i(9, 0, 0, 1, 7'h13));
        emit(fd, encode_i(4, 0, 0, 2, 7'h13));
        emit(fd, encode_r(0, 2, 1, 0, 3));
        emit(fd, encode_r(32, 2, 1, 0, 4));
        emit(fd, encode_r(0, 2, 1, 7, 5));
        emit(fd, encode_r(0, 2, 1, 6, 6));
        emit(fd, encode_r(0, 2, 1, 4, 7));
        emit(fd, encode_r(0, 1, 2, 2, 8));
        emit(fd, encode_r(0, 2, 1, 3, 9));
        emit(fd, encode_r(0, 2, 2, 1, 10));
        emit(fd, encode_r(0, 2, 10, 5, 11));
        emit(fd, encode_i(-16, 0, 0, 12, 7'h13));
        emit(fd, encode_r(32, 2, 12, 5, 13));
        emit(fd, encode_i(-5, 12, 2, 14, 7'h13));
        emit(fd, encode_i(-5, 12, 3, 15, 7'h13));
        emit(fd, encode_i(7, 1, 4, 16, 7'h13));
        emit(fd, encode_i(1, 2, 6, 17, 7'h13));
        emit(fd, encode_i(8, 1, 7, 18, 7'h13));
        emit(fd, encode_i(3, 2, 1, 19, 7'h13));
        emit(fd, encode_i(2, 19, 5, 20, 7'h13));
        emit(fd, encode_i(1026, 12, 5, 21, 7'h13));
        emit(fd, encode_u('h12000, 22, 7'h37));
        emit(fd, encode_u(0, 23, 7'h17));
        emit(fd, encode_i(9, 0, 0, 0, 7'h13));
        emit(fd, encode_r(0, 2, 12, 2, 24));
        emit(fd, encode_r(0, 2, 12, 3, 25));
        emit(fd, 32'h00000073);
        $fclose(fd);
    endtask

    task automatic create_memory();
        integer fd;
        fd = $fopen("memory.bin", "wb");
        if (fd == 0) $fatal(1, "No se pudo crear memory.bin");
        emit(fd, encode_u('h1000, 1, 7'h37));
        emit(fd, encode_i(-1, 0, 0, 2, 7'h13));
        emit(fd, encode_s(0, 2, 1, 2));
        emit(fd, encode_i(0, 1, 0, 3, 7'h03));
        emit(fd, encode_i(0, 1, 4, 4, 7'h03));
        emit(fd, encode_i(0, 1, 1, 5, 7'h03));
        emit(fd, encode_i(0, 1, 5, 6, 7'h03));
        emit(fd, encode_s(1, 0, 1, 0));
        emit(fd, encode_i(0, 1, 2, 7, 7'h03));
        emit(fd, encode_i('h123, 0, 0, 8, 7'h13));
        emit(fd, encode_s(4, 8, 1, 1));
        emit(fd, encode_i(4, 1, 5, 9, 7'h03));
        emit(fd, 32'h00000073);
        $fclose(fd);
    endtask

    task automatic create_branches();
        integer fd;
        fd = $fopen("branches.bin", "wb");
        if (fd == 0) $fatal(1, "No se pudo crear branches.bin");
        emit(fd, encode_i(1, 0, 0, 1, 7'h13));
        emit(fd, encode_i(0, 0, 0, 2, 7'h13));
        emit(fd, encode_i(6, 0, 0, 3, 7'h13));
        emit(fd, encode_r(0, 1, 2, 0, 2));
        emit(fd, encode_i(1, 1, 0, 1, 7'h13));
        emit(fd, encode_b(-8, 3, 1, 4));
        emit(fd, encode_u('h1000, 4, 7'h37));
        emit(fd, encode_s(8, 2, 4, 2));
        emit(fd, encode_b(8, 3, 2, 1));
        emit(fd, encode_i(99, 0, 0, 7, 7'h13));
        emit(fd, encode_b(8, 3, 1, 0));
        emit(fd, encode_i(99, 0, 0, 8, 7'h13));
        emit(fd, encode_b(8, 3, 1, 5));
        emit(fd, encode_i(99, 0, 0, 9, 7'h13));
        emit(fd, encode_b(8, 2, 3, 6));
        emit(fd, encode_i(99, 0, 0, 10, 7'h13));
        emit(fd, encode_b(8, 3, 2, 7));
        emit(fd, encode_i(99, 0, 0, 11, 7'h13));
        emit(fd, 32'h00000073);
        $fclose(fd);
    endtask

    task automatic create_jumps();
        integer fd;
        fd = $fopen("jumps.bin", "wb");
        if (fd == 0) $fatal(1, "No se pudo crear jumps.bin");
        emit(fd, encode_i(2, 0, 0, 5, 7'h13));
        emit(fd, encode_j(12, 1));
        emit(fd, encode_i(10, 5, 0, 5, 7'h13));
        emit(fd, 32'h00000073);
        emit(fd, encode_i(3, 5, 0, 5, 7'h13));
        emit(fd, encode_i(0, 1, 0, 0, 7'h67));
        $fclose(fd);
    endtask

    task automatic one_step();
        #1;
        step = 1;
        #2;
        clk = 1;
        #2;
        clk = 0;
        step = 0;
        #1;
    endtask

    task automatic execute_case(input string filename);
        $display("\n=======================================================");
        dut.load_program(filename);
        $display("=======================================================");
        while (dut.steps < STEP_LIMIT && !halted && !error)
            one_step();
        if (!halted && !error)
            $display("PAUSA: limite de %0d instrucciones alcanzado", STEP_LIMIT);
        else if (error)
            $display("FINAL: error de ejecucion");
        else
            $display("FINAL: programa detenido correctamente");
        dut.dump_registers();
        dut.dump_memory(32'h00001000, 16);
    endtask

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            $display("FALLO: %s", name);
            $fatal(1, "La prueba no paso");
        end
        $display("OK: %s", name);
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, clk, step, pc, halted, error, debug_x1, debug_x2, debug_x3, debug_x5, debug_a0);
        create_arithmetic();
        create_memory();
        create_branches();
        create_jumps();

        if (SELECT_CASE == 0 || SELECT_CASE == 1) begin
            execute_case("arithmetic.bin");
            if (halted && !error) begin
                check("Aritmetica y logica", dut.regs[3] == 13 && dut.regs[4] == 5 && dut.regs[6] == 13 && dut.regs[7] == 13);
                check("Comparaciones", dut.regs[8] == 1 && dut.regs[9] == 0 && dut.regs[14] == 1 && dut.regs[15] == 1 && dut.regs[24] == 1 && dut.regs[25] == 0);
                check("Desplazamientos", dut.regs[10] == 64 && dut.regs[11] == 4 && dut.regs[13] == 32'hffffffff && dut.regs[19] == 32 && dut.regs[20] == 8 && dut.regs[21] == 32'hfffffffc);
                check("Inmediatos y PC", dut.regs[16] == 14 && dut.regs[17] == 5 && dut.regs[18] == 8 && dut.regs[22] == 'h12000 && dut.regs[23] == 88 && dut.regs[0] == 0);
            end
        end
        if (SELECT_CASE == 0 || SELECT_CASE == 2) begin
            execute_case("memory.bin");
            if (halted && !error) begin
                check("Carga con signo", dut.regs[3] == 32'hffffffff && dut.regs[5] == 32'hffffffff);
                check("Carga sin signo", dut.regs[4] == 255 && dut.regs[6] == 65535 && dut.regs[9] == 'h123);
                check("Little endian", dut.read_memory(32'h00001000, 4) == 32'hffff00ff && dut.read_memory(32'h00001004, 2) == 32'h0123);
                check("Load word", dut.regs[7] == 32'hffff00ff);
            end
        end
        if (SELECT_CASE == 0 || SELECT_CASE == 3) begin
            execute_case("branches.bin");
            if (halted && !error) begin
                check("Bucle con BLT", dut.regs[1] == 6 && dut.regs[2] == 15);
                check("Branches condicionales", dut.regs[7] == 0 && dut.regs[8] == 0 && dut.regs[9] == 0 && dut.regs[10] == 0 && dut.regs[11] == 0);
                check("Resultado en memoria", dut.read_memory(32'h00001008, 4) == 15);
            end
        end
        if (SELECT_CASE == 0 || SELECT_CASE == 4) begin
            execute_case("jumps.bin");
            if (halted && !error) begin
                check("JAL y JALR", dut.regs[1] == 8 && dut.regs[5] == 15);
            end
        end
        $display("\nPRUEBAS FINALIZADAS");
        $finish;
    end

endmodule
