#!/usr/bin/python3

import os
import sys

import AppKit
import objc
import Quartz


PAGE_WIDTH = 612
PAGE_HEIGHT = 792
PIXEL_WIDTH = 1275
PIXEL_HEIGHT = 1650
LINE_COUNT = 40

TEXT_BLOCKS = (
    "사람이 읽는 문서는 일정한 문장과 숫자, 구두점을 함께 포함합니다. Reliable OCR should preserve words, numbers, and punctuation.",
    "측정 가능한 기준은 추측보다 유용하며 반복 실행으로 변화를 확인합니다. A reproducible benchmark turns intuition into evidence.",
    "페이지 순서와 문단 경계는 긴 문서를 처리할 때 반드시 유지되어야 합니다. Page identity makes ordering errors easy to detect.",
    "빠른 처리는 정확한 결과와 안정적인 자원 사용을 함께 만족해야 합니다. Throughput, accuracy, and memory all matter in production.",
    "한국어와 English가 섞인 본문은 실제 업무 문서에서 흔히 발견됩니다. Mixed-language lines provide realistic recognition work.",
    "고정된 입력 자료는 버전 사이의 성능 차이를 공정하게 비교하게 합니다. Deterministic content keeps comparisons meaningful.",
)


def bitmap_for_page(page_number):
    bitmap = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, PIXEL_WIDTH, PIXEL_HEIGHT, 8, 4, True, False,
        AppKit.NSCalibratedRGBColorSpace, 0, 0
    )
    context = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(bitmap)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(context)

    AppKit.NSColor.whiteColor().setFill()
    AppKit.NSRectFill(AppKit.NSMakeRect(0, 0, PIXEL_WIDTH, PIXEL_HEIGHT))

    font = AppKit.NSFont.fontWithName_size_("Apple SD Gothic Neo", 18)
    if font is None:
        font = AppKit.NSFont.systemFontOfSize_(18)
    bold_font = AppKit.NSFont.boldSystemFontOfSize_(24)
    body_attributes = {
        AppKit.NSFontAttributeName: font,
        AppKit.NSForegroundColorAttributeName: AppKit.NSColor.blackColor(),
    }
    header_attributes = {
        AppKit.NSFontAttributeName: bold_font,
        AppKit.NSForegroundColorAttributeName: AppKit.NSColor.blackColor(),
    }

    header = "Apple Vision OCR dense fixture — Page {:03d}".format(page_number)
    AppKit.NSAttributedString.alloc().initWithString_attributes_(
        header, header_attributes
    ).drawAtPoint_(AppKit.NSMakePoint(75, 1570))

    for line_index in range(LINE_COUNT):
        block = TEXT_BLOCKS[(page_number + line_index - 1) % len(TEXT_BLOCKS)]
        line = "P{:03d}-L{:02d}  {}".format(page_number, line_index + 1, block)
        AppKit.NSAttributedString.alloc().initWithString_attributes_(
            line, body_attributes
        ).drawInRect_(AppKit.NSMakeRect(75, 1515 - line_index * 35, 1125, 28))

    AppKit.NSGraphicsContext.restoreGraphicsState()
    return bitmap.CGImage()


def write_pdf(output_path, page_count):
    output_url = AppKit.NSURL.fileURLWithPath_(output_path)
    media_box = Quartz.CGRectMake(0, 0, PAGE_WIDTH, PAGE_HEIGHT)
    context = Quartz.CGPDFContextCreateWithURL(output_url, media_box, None)
    if context is None:
        raise RuntimeError("failed to create PDF: {}".format(output_path))

    for page_number in range(1, page_count + 1):
        Quartz.CGContextBeginPage(context, media_box)
        Quartz.CGContextDrawImage(context, media_box, bitmap_for_page(page_number))
        Quartz.CGContextEndPage(context)
    Quartz.CGPDFContextClose(context)


def assert_raster_only(output_path, page_count):
    AppKit.NSBundle.bundleWithPath_(
        "/System/Library/Frameworks/PDFKit.framework"
    ).load()
    pdf_document_class = objc.lookUpClass("PDFDocument")
    document = pdf_document_class.alloc().initWithURL_(
        AppKit.NSURL.fileURLWithPath_(output_path)
    )
    if document is None or document.pageCount() != page_count:
        raise AssertionError("PDFKit could not reopen all generated pages")

    for index in range(page_count):
        page_text = document.pageAtIndex_(index).string() or ""
        if page_text.strip():
            raise AssertionError("page {} contains a selectable text layer".format(index + 1))
    print("PDFKit no-text-layer assertion: PASS ({} pages)".format(page_count))


def main():
    if len(sys.argv) != 3:
        print("Usage: {} OUTPUT.pdf PAGE_COUNT".format(sys.argv[0]), file=sys.stderr)
        return 2

    output_path = os.path.abspath(sys.argv[1])
    try:
        page_count = int(sys.argv[2])
    except ValueError:
        print("PAGE_COUNT must be a positive integer", file=sys.stderr)
        return 2
    if page_count < 1:
        print("PAGE_COUNT must be a positive integer", file=sys.stderr)
        return 2

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    write_pdf(output_path, page_count)
    print("Generated {} raster pages: {}".format(page_count, output_path))
    assert_raster_only(output_path, page_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
