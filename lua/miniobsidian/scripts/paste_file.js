/**
 * paste_file.js — macOS JXA (JavaScript for Automation) 脚本
 *
 * 职责：从 macOS 剪贴板读取文件或图片，统一写入由 Lua 提供的临时目录，
 *       并通过 stdout 返回 JSON 元数据数组，供 Lua 端决定最终命名与 Markdown 链接格式。
 *
 * 返回的数组每项包含：
 *   - temp_path:     脚本写入的临时文件绝对路径
 *   - ext:           小写扩展名（jpeg 会被规范化为 jpg；无扩展名时为 ""）
 *   - original_name: 仅对 Finder 复制文件有效，为原始文件名；图片数据此项不存在
 *
 * 调用方式：
 *   osascript -l JavaScript paste_file.js <temp_directory>
 *
 * 退出码：
 *   0  成功，stdout 输出 JSON 数组
 *   1  失败，stderr 输出包含以下关键字之一：
 *      NO_CONTENT    — 剪贴板中既无文件也无图片
 *      READ_FAILED   — 读取源文件失败
 *      WRITE_FAILED  — 写入临时文件失败
 *      TIFF_FAILED   — 无法获取图片 TIFF 表示
 *      BITMAP_FAILED — 无法创建位图表示
 *      CONVERT_FAILED— 格式转换失败
 *      MISSING_PATH  — 未提供临时目录参数
 */

/* global $, ObjC */
ObjC.import("AppKit");
ObjC.import("Foundation");

/** 从路径字符串中提取扩展名（小写，不含点） */
function getExt(filePath) {
  const parts = filePath.split(".");
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : "";
}

/** 规范化扩展名：jpeg → jpg */
function normalizeExt(ext) {
  return ext === "jpeg" ? "jpg" : ext;
}

function run(argv) {
  if (!argv || argv.length < 1) {
    throw new Error("MISSING_PATH");
  }

  const tempDir = argv[0];
  const pb = $.NSPasteboard.generalPasteboard;

  // 临时目录由 Lua 端（vim.fn.mkdir）提前创建，这里无需再创建。

  const result = [];

  // ── 路径 1：Finder 复制的文件列表（NSFilenamesPboardType）────────────
  // 支持任意类型文件，按原样逐字节复制到临时目录，保留原始扩展名。
  const fileList = pb.propertyListForType($("NSFilenamesPboardType"));
  if (!fileList.isNil() && fileList.count > 0) {
    for (let i = 0; i < fileList.count; i++) {
      const srcPath = fileList.objectAtIndex(i).js;
      const srcExt = getExt(srcPath);
      const normalExt = normalizeExt(srcExt);

      const tempName = "paste-" + i + (normalExt ? "." + normalExt : "");
      const tempPath = tempDir + "/" + tempName;

      const srcURL = $.NSURL.fileURLWithPath($(srcPath));
      const data = $.NSData.dataWithContentsOfURL(srcURL);
      if (data.isNil()) {
        throw new Error("READ_FAILED");
      }

      const dstURL = $.NSURL.fileURLWithPath($(tempPath));
      if (!data.writeToURLAtomically(dstURL, true)) {
        throw new Error("WRITE_FAILED");
      }

      result.push({
        temp_path: tempPath,
        ext: normalExt,
        original_name: srcPath.split("/").pop(),
      });
    }
    return JSON.stringify(result);
  }

  // ── 路径 2：截图 / 浏览器复制图片（NSImage 流水线）───────────────────
  const image = $.NSImage.alloc.initWithPasteboard(pb);
  if (image.isNil()) {
    throw new Error("NO_CONTENT");
  }

  const nsTypes = pb.types;
  const typeCount = nsTypes.isNil() ? 0 : nsTypes.count;
  const types = [];
  for (let i = 0; i < typeCount; i++) {
    const t = nsTypes.objectAtIndex(i).js;
    if (t) types.push(t);
  }

  // UTI 优先级：JPEG > GIF > PNG（PNG 兜底，覆盖 TIFF/截图等所有其他情形）
  let ext, fileType;
  if (types.includes("public.jpeg")) {
    ext = "jpg";
    fileType = $.NSBitmapImageFileTypeJPEG;
  } else if (types.includes("com.compuserve.gif")) {
    ext = "gif";
    fileType = $.NSBitmapImageFileTypeGIF;
  } else {
    ext = "png";
    fileType = $.NSBitmapImageFileTypePNG;
  }

  const tiff = image.TIFFRepresentation;
  if (tiff.isNil()) {
    throw new Error("TIFF_FAILED");
  }

  const bitmap = $.NSBitmapImageRep.imageRepWithData(tiff);
  if (bitmap.isNil()) {
    throw new Error("BITMAP_FAILED");
  }

  const data = bitmap.representationUsingTypeProperties(fileType, $());
  if (data.isNil()) {
    throw new Error("CONVERT_FAILED");
  }

  const tempPath = tempDir + "/paste-0." + ext;
  const url = $.NSURL.fileURLWithPath($(tempPath));
  if (!data.writeToURLAtomically(url, true)) {
    throw new Error("WRITE_FAILED");
  }

  // 图片数据没有原始文件名，Lua 端会使用用户输入或时间戳
  result.push({ temp_path: tempPath, ext: ext });
  return JSON.stringify(result);
}
