module riscv32_sim (
    input logic clk,
    input logic step,
    output logic [31:0] pc,
    output logic halted,
    output logic error
);

    reg [31:0] regs [0:31];
    reg [7:0] memory [0:2097151];
    reg [19:0] page_tag [0:2047];
    integer page_frame [0:2047];
    reg page_valid [0:2047];
    integer allocated_pages;
    integer program_size;
    integer steps;
    string error_text;

    function automatic [7:0] read_byte(input [31:0] addr);
        reg [19:0] page;
        integer slot;
        integer tries;
        integer offset;
        reg found;
        begin
            page = addr[31:12];
            offset = addr[11:0];
            slot = (page ^ (page >> 11)) & 2047;
            tries = 0;
            found = 0;
            while (tries < 2048 && page_valid[slot] && !found) begin
                if (page_tag[slot] == page)
                    found = 1;
                else begin
                    slot = (slot + 1) & 2047;
                    tries = tries + 1;
                end
            end
            if (found)
                read_byte = memory[page_frame[slot] * 4096 + offset];
            else
                read_byte = 8'h00;
        end
    endfunction

    task automatic write_byte(input [31:0] addr, input [7:0] value);
        reg [19:0] page;
        integer slot;
        integer tries;
        integer offset;
        integer i;
        reg found;
        begin
            page = addr[31:12];
            offset = addr[11:0];
            slot = (page ^ (page >> 11)) & 2047;
            tries = 0;
            found = 0;
            while (tries < 2048 && page_valid[slot] && !found) begin
                if (page_tag[slot] == page)
                    found = 1;
                else begin
                    slot = (slot + 1) & 2047;
                    tries = tries + 1;
                end
            end
            if (tries >= 2048 || allocated_pages >= 512) begin
                $fatal(1, "Sin memoria fisica disponible");
            end else begin
                if (!found) begin
                    page_valid[slot] = 1;
                    page_tag[slot] = page;
                    page_frame[slot] = allocated_pages;
                    for (i = 0; i < 4096; i = i + 1)
                        memory[allocated_pages * 4096 + i] = 0;
                    allocated_pages = allocated_pages + 1;
                end
                memory[page_frame[slot] * 4096 + offset] = value;
            end
        end
    endtask

    function automatic [31:0] read_memory(input [31:0] addr, input integer count);
        reg [31:0] value;
        integer i;
        begin
            value = 0;
            for (i = 0; i < count; i = i + 1)
                value[i*8 +: 8] = read_byte(addr + i);
            read_memory = value;
        end
    endfunction

    task automatic write_memory(input [31:0] addr, input integer count, input [31:0] value);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                write_byte(addr + i, value[i*8 +: 8]);
        end
    endtask

    task automatic load_program(input string filename);
        integer fd;
        integer character;
        integer i;
        begin
            for (i = 0; i < 2048; i = i + 1)
                page_valid[i] = 0;
            allocated_pages = 0;
            for (i = 0; i < 32; i = i + 1)
                regs[i] = 0;
            pc = 0;
            halted = 0;
            error = 0;
            steps = 0;
            program_size = 0;
            error_text = "";
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                halted = 1;
                error = 1;
                error_text = "No se pudo abrir el archivo";
                $display("ERROR: %s: %s", error_text, filename);
            end else begin
                character = $fgetc(fd);
                while (character != -1 && program_size < 1048576) begin
                    write_byte(program_size, character[7:0]);
                    program_size = program_size + 1;
                    character = $fgetc(fd);
                end
                $fclose(fd);
                if (character != -1 || program_size == 0) begin
                    halted = 1;
                    error = 1;
                    error_text = "Binario vacio o superior a 1 MiB";
                    $display("ERROR: %s", error_text);
                end else begin
                    $display("PROGRAMA CARGADO: %s | %0d bytes | PC=%08h", filename, program_size, pc);
                end
            end
        end
    endtask

    task automatic trap(input string reason, input logic [31:0] instruction);
        error = 1;
        halted = 1;
        error_text = reason;
        $display("ERROR PC=%08h INSTRUCCION=%08h: %s", pc, instruction, reason);
    endtask

    task automatic dump_registers();
        $display("REGISTROS | PC=%08h | PASOS=%0d", pc, steps);
        for (int i = 0; i < 32; i++)
            $display("x%02d = 0x%08h (%0d)", i, regs[i], $signed(regs[i]));
    endtask

    task automatic dump_memory(input logic [31:0] addr, input int count);
        $display("MEMORIA DESDE 0x%08h | %0d BYTES", addr, count);
        for (int i = 0; i < count; i++) begin
            if (i % 16 == 0)
                $write("%08h: ", addr + i);
            $write("%02h ", read_byte(addr + i));
            if (i % 16 == 15 || i == count - 1)
                $write("\n");
        end
    endtask

    always @(posedge clk) begin : execute
        logic [31:0] ins;
        logic [31:0] old_pc;
        logic [31:0] next_pc;
        logic [31:0] imm_i;
        logic [31:0] imm_s;
        logic [31:0] imm_b;
        logic [31:0] imm_u;
        logic [31:0] imm_j;
        logic [31:0] a;
        logic [31:0] b;
        logic [31:0] result;
        logic [31:0] addr;
        logic [31:0] data_value;
        logic [6:0] opcode;
        logic [6:0] funct7;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic write_rd;
        logic valid;
        string mnemonic;

        if (step && !halted) begin
            if (pc[1:0] != 2'b00) begin
                trap("PC no alineado a 4 bytes", 0);
            end else begin
                old_pc = pc;
                ins = read_memory(pc, 4);
                opcode = ins[6:0];
                rd = ins[11:7];
                funct3 = ins[14:12];
                rs1 = ins[19:15];
                rs2 = ins[24:20];
                funct7 = ins[31:25];
                imm_i = {{20{ins[31]}}, ins[31:20]};
                imm_s = {{20{ins[31]}}, ins[31:25], ins[11:7]};
                imm_b = {{19{ins[31]}}, ins[31], ins[7], ins[30:25], ins[11:8], 1'b0};
                imm_u = {ins[31:12], 12'b0};
                imm_j = {{11{ins[31]}}, ins[31], ins[19:12], ins[20], ins[30:21], 1'b0};
                a = regs[rs1];
                b = regs[rs2];
                next_pc = pc + 4;
                result = 0;
                write_rd = 0;
                valid = 1;
                mnemonic = "";

                case (opcode)
                    7'h03: begin
                        addr = a + imm_i;
                        write_rd = 1;
                        case (funct3)
                            3'b000: begin data_value = read_memory(addr, 1); result = {{24{data_value[7]}}, data_value[7:0]}; mnemonic = "LB"; end
                            3'b001: begin data_value = read_memory(addr, 2); result = {{16{data_value[15]}}, data_value[15:0]}; mnemonic = "LH"; end
                            3'b010: begin result = read_memory(addr, 4); mnemonic = "LW"; end
                            3'b100: begin result = read_memory(addr, 1); mnemonic = "LBU"; end
                            3'b101: begin result = read_memory(addr, 2); mnemonic = "LHU"; end
                            default: valid = 0;
                        endcase
                    end
                    7'h13: begin
                        write_rd = 1;
                        case (funct3)
                            3'b000: begin result = a + imm_i; mnemonic = "ADDI"; end
                            3'b010: begin result = ($signed(a) < $signed(imm_i)); mnemonic = "SLTI"; end
                            3'b011: begin result = (a < imm_i); mnemonic = "SLTIU"; end
                            3'b100: begin result = a ^ imm_i; mnemonic = "XORI"; end
                            3'b110: begin result = a | imm_i; mnemonic = "ORI"; end
                            3'b111: begin result = a & imm_i; mnemonic = "ANDI"; end
                            3'b001: begin
                                if (funct7 == 7'h00) begin
                                    result = a << ins[24:20];
                                    mnemonic = "SLLI";
                                end else valid = 0;
                            end
                            3'b101: begin
                                if (funct7 == 7'h00) begin
                                    result = a >> ins[24:20];
                                    mnemonic = "SRLI";
                                end else if (funct7 == 7'h20) begin
                                    result = $signed(a) >>> ins[24:20];
                                    mnemonic = "SRAI";
                                end else valid = 0;
                            end
                            default: valid = 0;
                        endcase
                    end
                    7'h17: begin result = old_pc + imm_u; write_rd = 1; mnemonic = "AUIPC"; end
                    7'h23: begin
                        addr = a + imm_s;
                        case (funct3)
                            3'b000: begin write_memory(addr, 1, b); mnemonic = "SB"; end
                            3'b001: begin write_memory(addr, 2, b); mnemonic = "SH"; end
                            3'b010: begin write_memory(addr, 4, b); mnemonic = "SW"; end
                            default: valid = 0;
                        endcase
                    end
                    7'h33: begin
                        write_rd = 1;
                        case (funct3)
                            3'b000: begin
                                if (funct7 == 7'h00) begin result = a + b; mnemonic = "ADD"; end
                                else if (funct7 == 7'h20) begin result = a - b; mnemonic = "SUB"; end
                                else valid = 0;
                            end
                            3'b001: begin
                                if (funct7 == 7'h00) begin result = a << b[4:0]; mnemonic = "SLL"; end
                                else valid = 0;
                            end
                            3'b010: begin
                                if (funct7 == 7'h00) begin result = ($signed(a) < $signed(b)); mnemonic = "SLT"; end
                                else valid = 0;
                            end
                            3'b011: begin
                                if (funct7 == 7'h00) begin result = (a < b); mnemonic = "SLTU"; end
                                else valid = 0;
                            end
                            3'b100: begin
                                if (funct7 == 7'h00) begin result = a ^ b; mnemonic = "XOR"; end
                                else valid = 0;
                            end
                            3'b101: begin
                                if (funct7 == 7'h00) begin result = a >> b[4:0]; mnemonic = "SRL"; end
                                else if (funct7 == 7'h20) begin result = $signed(a) >>> b[4:0]; mnemonic = "SRA"; end
                                else valid = 0;
                            end
                            3'b110: begin
                                if (funct7 == 7'h00) begin result = a | b; mnemonic = "OR"; end
                                else valid = 0;
                            end
                            3'b111: begin
                                if (funct7 == 7'h00) begin result = a & b; mnemonic = "AND"; end
                                else valid = 0;
                            end
                            default: valid = 0;
                        endcase
                    end
                    7'h37: begin result = imm_u; write_rd = 1; mnemonic = "LUI"; end
                    7'h63: begin
                        case (funct3)
                            3'b000: begin if (a == b) next_pc = old_pc + imm_b; mnemonic = "BEQ"; end
                            3'b001: begin if (a != b) next_pc = old_pc + imm_b; mnemonic = "BNE"; end
                            3'b100: begin if ($signed(a) < $signed(b)) next_pc = old_pc + imm_b; mnemonic = "BLT"; end
                            3'b101: begin if ($signed(a) >= $signed(b)) next_pc = old_pc + imm_b; mnemonic = "BGE"; end
                            3'b110: begin if (a < b) next_pc = old_pc + imm_b; mnemonic = "BLTU"; end
                            3'b111: begin if (a >= b) next_pc = old_pc + imm_b; mnemonic = "BGEU"; end
                            default: valid = 0;
                        endcase
                    end
                    7'h67: begin
                        if (funct3 == 3'b000) begin
                            result = old_pc + 4;
                            next_pc = (a + imm_i) & 32'hfffffffe;
                            write_rd = 1;
                            mnemonic = "JALR";
                        end else valid = 0;
                    end
                    7'h6f: begin
                        result = old_pc + 4;
                        next_pc = old_pc + imm_j;
                        write_rd = 1;
                        mnemonic = "JAL";
                    end
                    7'h73: begin
                        if (ins == 32'h00000073) begin
                            mnemonic = "ECALL";
                            halted = 1;
                        end else if (ins == 32'h00100073) begin
                            mnemonic = "EBREAK";
                            halted = 1;
                        end else valid = 0;
                    end
                    7'h0f: begin
                        if (funct3 == 3'b000) mnemonic = "FENCE";
                        else valid = 0;
                    end
                    default: valid = 0;
                endcase

                if (!valid) begin
                    trap("Instruccion RV32I invalida o no soportada", ins);
                end else begin
                    if (write_rd && rd != 0)
                        regs[rd] = result;
                    regs[0] = 0;
                    pc = next_pc;
                    steps++;
                    if (write_rd && rd != 0)
                        $display("PASO=%0d PC=%08h INS=%08h %-6s x%0d=%08h PC_NUEVO=%08h", steps, old_pc, ins, mnemonic, rd, regs[rd], pc);
                    else
                        $display("PASO=%0d PC=%08h INS=%08h %-6s PC_NUEVO=%08h", steps, old_pc, ins, mnemonic, pc);
                end
            end
        end
    end

endmodule
