const std = @import("std");
const StyleParser = @import("styleparser.zig");

const C = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_resize.h");
    @cInclude("stb_image_write.h");
    @cInclude("pdfgen.h");
});

const log = std.log.scoped(.pdf_gen);

const PDF_PAGE_OUTPUT_DPI: f32 = 300.0;

const A4_WIDTH_INCHES: f32 = 8.27;
const A4_HEIGHT_INCHES: f32 = 11.69;

const A4_WIDTH_PX: f32 = A4_WIDTH_INCHES * PDF_PAGE_OUTPUT_DPI;
const A4_HEIGHT_PX: f32 = A4_HEIGHT_INCHES * PDF_PAGE_OUTPUT_DPI;

const MARGIN_INCHES: f32 = 0.5;
const MARGIN_PX: f32 = MARGIN_INCHES * PDF_PAGE_OUTPUT_DPI;

const USABLE_PAGE_WIDTH_PX: f32 = A4_WIDTH_PX - (2 * MARGIN_PX);
const USABLE_PAGE_HEIGHT_PX: f32 = A4_HEIGHT_PX - (2 * MARGIN_PX);

const StbiWriteFuncContext = struct {
    allocator: std.mem.Allocator,
    cloned: ?[]const u8,
};

pub fn generateReceiptPdf(
    input_image_name: []const u8,
    input_image: []const u8,
    output_pdf_path: [*c]const u8,
    allocator: std.mem.Allocator,
) !void {
    var img_width: c_int = 0;
    var img_height: c_int = 0;
    var img_channels: c_int = 0;

    const image_data = C.stbi_load_from_memory(
        @ptrCast(input_image.ptr),
        @intCast(input_image.len),
        &img_width,
        &img_height,
        &img_channels,
        3, // we force to 3 channels
    );
    if (image_data == null) {
        log.err("Error: Failed to load image '{s}'. Image data is null.", .{input_image_name});
        return error.ImageLoadFailed;
    }
    defer C.stbi_image_free(image_data);

    if (img_width <= 0 or img_height <= 0) {
        log.err("IMAGE {s} HAS NEGATIVE DIMENSIONS ({d}x{d})", .{ input_image_name, img_width, img_height });
        return error.ImageInvalidDimensions;
    }

    if (img_channels != 3) {
        log.err("IMAGE {s} HAS {d} CHANNELS, expected 3", .{ input_image_name, img_channels });
        return error.InvalidImageChannels;
    }

    log.info(
        "Original Image: {d}x{d}px with {d} channels",
        .{ img_width, img_height, img_channels },
    );

    const original_img_width_f = @as(f32, @floatFromInt(img_width));
    const original_img_height_f = @as(f32, @floatFromInt(img_height));

    const scale_factor_w = USABLE_PAGE_WIDTH_PX / original_img_width_f;
    const scale_factor_h = USABLE_PAGE_HEIGHT_PX / original_img_height_f;

    const overall_scale_factor = @min(scale_factor_w, scale_factor_h);

    var final_resized_px_width: c_int = @intFromFloat(@round(
        original_img_width_f * overall_scale_factor,
    ));
    var final_resized_px_height: c_int = @intFromFloat(@round(
        original_img_height_f * overall_scale_factor,
    ));

    if (final_resized_px_width == 0) final_resized_px_width = 1;
    if (final_resized_px_height == 0) final_resized_px_height = 1;

    std.debug.assert(final_resized_px_width > 0 and final_resized_px_height > 0);

    log.info(
        "Image will be resized to: {d}x{d}px (to fit {d}x{d}px page area)",
        .{
            final_resized_px_width,
            final_resized_px_height,
            @as(u32, @intFromFloat(USABLE_PAGE_WIDTH_PX)),
            @as(u32, @intFromFloat(USABLE_PAGE_HEIGHT_PX)),
        },
    );

    const total_resized_pixels: u64 = @as(u64, @intCast(final_resized_px_width)) * @as(u64, @intCast(final_resized_px_height));
    const resized_image_data_buffer_len: usize = @as(usize, total_resized_pixels * @as(u64, @intCast(img_channels)));
    const resized_image_data_buffer = try allocator.alloc(u8, resized_image_data_buffer_len);
    defer allocator.free(resized_image_data_buffer);

    const resize_result = C.stbir_resize_uint8(
        image_data,
        img_width,
        img_height,
        0, // input stride
        resized_image_data_buffer.ptr,
        final_resized_px_width,
        final_resized_px_height,
        0, // output strides
        img_channels,
    );
    if (resize_result == 0) {
        log.err("Error: stbir_resize_uint8 failed (returned 0).", .{});
        return error.ImageResizeFailed;
    }
    log.info("image resized successfully", .{});

    const JPG_QUALITY: c_int = 0;
    _ = JPG_QUALITY;

    var write_jpg_context: StbiWriteFuncContext = .{
        .allocator = allocator,
        .cloned = null, // <-- stbi we will use allocator to clone into here
    };
    defer {
        if (write_jpg_context.cloned) |cloned| {
            allocator.free(cloned);
        }
    }

    const write_jpg_result = C.stbi_write_png_to_func(
        stbi_write_func_zig_wrapper_impl,
        &write_jpg_context,
        final_resized_px_width,
        final_resized_px_height,
        img_channels,
        resized_image_data_buffer.ptr,
        0,
    );
    if (write_jpg_result == 0 or write_jpg_context.cloned == null) {
        log.err("Error: Failed to write JPEG data to buffer.", .{});
        return error.ImageWriteFailed;
    }

    log.info(
        "JPEG data successfully written to memory buffer (len={d}).",
        .{write_jpg_context.cloned.?.len},
    );

    var info: C.pdf_info = .{};
    _ = try std.fmt.bufPrintZ(
        &info.producer,
        "{s}",
        .{"fj - The Commandline Company"},
    );

    const pdf_doc = C.pdf_create(A4_WIDTH_PX, A4_HEIGHT_PX, &info);
    if (pdf_doc == null) {
        return error.PdfCreateFailed;
    }
    defer C.pdf_destroy(pdf_doc);

    const page = C.pdf_append_page(pdf_doc);

    const image_x_offset_px = MARGIN_PX + (USABLE_PAGE_WIDTH_PX - @as(f32, @floatFromInt(final_resized_px_width))) / 2.0;
    const image_y_offset_px = MARGIN_PX + (USABLE_PAGE_HEIGHT_PX - @as(f32, @floatFromInt(final_resized_px_height))) / 2.0;

    _ = C.pdf_add_image_data(
        pdf_doc,
        page,
        image_x_offset_px,
        image_y_offset_px,
        @as(f32, @floatFromInt(final_resized_px_width)),
        @as(f32, @floatFromInt(final_resized_px_height)),
        write_jpg_context.cloned.?.ptr,
        write_jpg_context.cloned.?.len,
    );

    if (C.pdf_save(pdf_doc, output_pdf_path) < 0) {
        return error.PdfSave;
    }
    log.info(
        "PDF '{s}' with image (placed as {d:.2}x{d:.2}px) generated successfully",
        .{ output_pdf_path, final_resized_px_width, final_resized_px_height },
    );
}
fn stbi_write_func_zig_wrapper_impl(
    context: ?*anyopaque,
    data_ptr: ?*anyopaque,
    size: c_int,
) callconv(.c) void {
    var ctx: *StbiWriteFuncContext = @ptrCast(@alignCast(context.?));

    var data_slice: []const u8 = undefined;
    data_slice.ptr = @ptrCast(data_ptr.?);
    data_slice.len = @intCast(size);

    // we take a copy because we don't know when stdbi will deallocate
    if (ctx.allocator.dupe(u8, data_slice)) |slice| {
        ctx.cloned = slice;
    } else |_| {
        ctx.cloned = null;
    }
}

fn stbi_write_func_zig_wrapper_impl_old(
    context: ?*anyopaque,
    data_ptr: ?*anyopaque,
    size: c_int,
) callconv(.c) void {
    const jpg_output_alist: *std.ArrayList(u8) = @ptrCast(@alignCast(context.?));

    var data_slice: []const u8 = undefined;
    data_slice.ptr = @ptrCast(data_ptr.?);
    data_slice.len = @intCast(size);
    jpg_output_alist.appendSlice(data_slice) catch unreachable;
}

fn pdf_get_text_width(pdf: ?*C.struct_pdf_doc, font_name: [*c]const u8, text: [*c]const u8, size: f32) !f32 {
    var ret: f32 = undefined;
    if (C.pdf_get_font_text_width(pdf, font_name, text, size, &ret) < 0) {
        return error.PdfGetTextWidth;
    }
    return ret;
}

pub fn generateProtocolPdf(
    arena: std.mem.Allocator,
    filename: []const u8,
    protocol_content: []const u8,
) !void {
    var info: C.pdf_info = .{};
    _ = try std.fmt.bufPrintZ(&info.producer, "{s}", .{"fj - The Commandline Company"});

    // Protokoll-PDF erstellt mit Pixel-Dimensionen der A4-Seite
    const protocol_pdf_doc = C.pdf_create(A4_WIDTH_PX, A4_HEIGHT_PX, &info);
    if (protocol_pdf_doc == null) {
        return error.PdfCreateFailed;
    }
    defer C.pdf_destroy(protocol_pdf_doc);

    const page_protocol = C.pdf_append_page(protocol_pdf_doc);

    // font size and y pos need to be adjusted according to the page output dpi
    const font_size_base: f32 = 12.0; // base font size
    var font_size_scaled = font_size_base * (PDF_PAGE_OUTPUT_DPI / 72.0);
    var current_y = A4_HEIGHT_PX - MARGIN_PX - 5 * font_size_scaled;

    var lines = std.mem.splitScalar(u8, protocol_content, '\n');
    while (lines.next()) |line| {
        font_size_scaled = font_size_base * (PDF_PAGE_OUTPUT_DPI / 72.0);
        var current_x = MARGIN_PX;

        for (try StyleParser.parse(arena, line)) |span| {
            const text, const font: [*]const u8 = blk: {
                switch (span) {
                    .heading => |s| {
                        font_size_scaled *= 1.5;
                        break :blk .{ s, "Helvetica-Bold" };
                    },
                    .bold => |s| {
                        break :blk .{ s, "Helvetica-Bold" };
                    },
                    .normal => |s| {
                        break :blk .{ s, "Helvetica" };
                    },
                }
            };

            if (C.pdf_set_font(protocol_pdf_doc, font) < 0) {
                return error.PdfFont;
            }
            const c_text_ptr = try arena.dupeZ(u8, text);
            const text_width = try pdf_get_text_width(protocol_pdf_doc, font, c_text_ptr, font_size_scaled);
            if (C.pdf_add_text(
                protocol_pdf_doc,
                page_protocol,
                c_text_ptr,
                font_size_scaled,
                current_x,
                current_y,
                0,
            ) < 0) return error.PdfText;
            std.debug.print(">>> `{s}`\n", .{text});
            current_x += text_width; // X-Position für den nächsten Text
        }

        current_y -= font_size_scaled * 1.3;
    }

    const filn = try arena.dupeZ(u8, filename);
    if (C.pdf_save(protocol_pdf_doc, filn) < 0) {
        return error.PdfSave;
    }
}
