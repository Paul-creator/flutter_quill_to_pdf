import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:dio/dio.dart';
import 'package:flutter_quill_delta_easy_parser/flutter_quill_delta_easy_parser.dart';
import 'package:flutter_quill_to_pdf/core/constant/constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_quill_to_pdf/flutter_quill_to_pdf.dart';
import '../../../utils/css.dart';
import 'attribute_functions.dart';
import 'document_functions.dart';

abstract class PdfConfigurator<T, D> extends ConverterConfigurator<T, D>
    implements
        AttrInlineFunctions<List<pw.InlineSpan>, pw.TextStyle?>,
        AttrBlockFunctions<pw.Widget, pw.TextStyle?>,
        DocumentFunctions<Delta, Document, List<pw.Widget>> {
  late final pw.ThemeData defaultTheme;
  late final PdfColor defaultLinkColor;
  late final pw.TextStyle defaultTextStyle;
  //show default this on ordered list
  int numberList = 0;
  int numCodeLine = 0;
  final Delta? frontM;
  final Delta? backM;
  @Deprecated('This option is not longer used by the converter and will be removed on future releases')
  final List<CustomConverter> customConverters;
  final List<CustomWidget<Object, Object>> customBuilders;
  final Future<pw.Font> Function(String fontFamily)? onRequestFont;
  final Future<pw.Font> Function(String fontFamily)? onRequestBoldFont;
  final Future<pw.Font> Function(String fontFamily)? onRequestItalicFont;
  final Future<pw.Font> Function(String fontFamily)? onRequestBothFont;
  final PDFWidgetBuilder<Line>? onDetectImageBlock;
  final PDFWidgetBuilder<Line>? onDetectInlineRichTextStyles;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectHeaderBlock;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectHeaderAlignedBlock;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectAlignedParagraph;
  final PDFWidgetBuilder<Line>? onDetectCommonText;

  @Deprecated('onDetectInlinesMarkdown is no longer used and will be removed on future releases')
  final CustomPDFWidget? onDetectInlinesMarkdown;
  final PDFWidgetBuilder<Line>? onDetectLink;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectList;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectCodeBlock;
  final PDFWidgetBuilder<List<pw.InlineSpan>>? onDetectBlockquote;
  final pw.Font? codeBlockFont;
  final pw.TextStyle? codeBlockTextStyle;
  final PdfColor? codeBlockBackgroundColor;
  final pw.TextStyle? codeBlockNumLinesTextStyle;
  final pw.TextStyle? blockQuoteTextStyle;
  final PdfColor? blockQuoteBackgroundColor;
  final PdfColor? blockQuoteDividerColor;
  final double? blockQuotethicknessDividerColor;
  final double? blockQuotePaddingLeft;
  final double? blockQuotePaddingRight;
  final Future<List<pw.Font>?> Function(String fontFamily)? onRequestFallbacks;
  final int defaultFontSize = Constant.DEFAULT_FONT_SIZE; //avoid spans without font sizes not appears in the document
  late final double pageWidth, pageHeight;
  PdfConfigurator({
    this.onRequestBoldFont,
    this.onRequestBothFont,
    this.onRequestFallbacks,
    this.onRequestFont,
    this.onRequestItalicFont,
    required this.customConverters,
    required this.customBuilders,
    required super.document,
    this.blockQuotePaddingLeft,
    this.blockQuotePaddingRight,
    this.blockQuotethicknessDividerColor,
    this.blockQuoteBackgroundColor,
    this.codeBlockBackgroundColor,
    this.codeBlockNumLinesTextStyle,
    this.codeBlockTextStyle,
    this.blockQuoteDividerColor,
    this.blockQuoteTextStyle,
    this.codeBlockFont,
    this.onDetectBlockquote,
    this.onDetectCodeBlock,
    this.onDetectAlignedParagraph,
    this.onDetectCommonText,
    this.onDetectHeaderAlignedBlock,
    this.onDetectHeaderBlock,
    this.onDetectInlinesMarkdown,
    this.onDetectLink,
    this.onDetectList,
    this.onDetectInlineRichTextStyles,
    this.onDetectImageBlock,
    this.backM,
    this.frontM,
  }) {
    defaultLinkColor = const PdfColor.fromInt(0x2AAB);
  }

  //Network image is not supported yet
  @override
  Future<pw.Widget> getImageBlock(Line line, [pw.Alignment? alignment]) async {
    double? width = null;
    double? height = null;
    final String path = (line.data as Map<String, dynamic>)['image'];
    final Map<String, dynamic> attributes = parseCssStyles(line.attributes?['style'] ?? '', 'left');
    if (attributes.isNotEmpty) {
      width = attributes['width'] ?? pageWidth;
      height = attributes['height'];
    }
    late final File? file;
    if (Constant.IMAGE_FROM_NETWORK_URL.hasMatch(path)) {
      final String url = path;
      final String pathStorage =
          '${(await getApplicationCacheDirectory()).path}/image (${Random.secure().nextInt(99999) + 50})';
      try {
        file = File(pathStorage);
        await Dio().download(url, pathStorage);
      } on DioException {
        rethrow;
      }
    }
    file = File(path);
    if ((await file.exists()) == false) {
      return pw.SizedBox.shrink();
    }
    // verify if exceded height using page format params
    if (height != null && height >= pageHeight) height = pageHeight;
    // verify if exceded width using page format params
    if (width != null && width >= pageWidth) width = pageWidth;
    return pw.RichText(
      softWrap: true,
      overflow: pw.TextOverflow.span,
      text: pw.WidgetSpan(
        child: pw.Container(
          alignment: alignment,
          constraints: height == null ? const pw.BoxConstraints(maxHeight: 450) : null,
          child: pw.Image(
            pw.MemoryImage((await file.readAsBytes())),
            dpi: 230,
            height: height,
            width: width,
          ),
        ),
      ),
    );
  }

  @override
  Future<List<pw.InlineSpan>> getRichTextInlineStyles(Line line,
      [pw.TextStyle? style, bool returnContentIfNeedIt = false, bool addFontSize = true]) async {
    final List<pw.InlineSpan> spans = <pw.InlineSpan>[];
    final PdfColor? textColor = pdfColorString(line.attributes?['color']);
    final PdfColor? backgroundTextColor = pdfColorString(line.attributes?['background']);
    final double? spacing = line.attributes?['line-height'];
    final String? fontFamily = line.attributes?['font'];
    final String? fontSizeMatch = line.attributes?['size'];
    double fontSizeHelper = defaultTextStyle.fontSize!;
    if (fontSizeMatch != null) {
      if (fontSizeMatch == 'small') fontSizeHelper = 8;
      if (fontSizeMatch == 'large') fontSizeHelper = 15.5;
      if (fontSizeMatch == 'huge') fontSizeHelper = 18.5;
      if (fontSizeMatch != 'huge' && fontSizeMatch != 'large' && fontSizeMatch != 'small') {
        fontSizeHelper = double.parse(fontSizeMatch);
      }
    }
    final bool bold = line.attributes?['bold'] ?? false;
    final bool italic = line.attributes?['italic'] ?? false;
    final bool strike = line.attributes?['strike'] ?? false;
    final bool underline = line.attributes?['underline'] ?? false;
    final double? fontSize = !addFontSize ? null : fontSizeHelper;
    final String content = line.data as String;
    final double? lineSpacing = spacing?.resolveLineHeight();
    final pw.Font font = await onRequestFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY);
    final List<pw.Font> fonts =
        await onRequestFallbacks?.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY) ?? <pw.Font>[];
    // Give just the necessary fallbacks for the founded fontFamily
    final pw.TextStyle decided_style = style?.copyWith(
          font: font,
          fontStyle: italic ? pw.FontStyle.italic : null,
          fontWeight: bold ? pw.FontWeight.bold : null,
          decoration: pw.TextDecoration.combine(<pw.TextDecoration>[
            if (strike) pw.TextDecoration.lineThrough,
            if (underline) pw.TextDecoration.underline,
          ]),
          decorationStyle: pw.TextDecorationStyle.solid,
          decorationColor: textColor ?? backgroundTextColor,
          fontBold: await onRequestBoldFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontItalic: await onRequestItalicFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontBoldItalic: await onRequestBothFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontFallback: fonts,
          fontSize: !addFontSize ? null : fontSize ?? defaultFontSize.toDouble(),
          lineSpacing: lineSpacing,
          color: textColor,
          background: pw.BoxDecoration(color: backgroundTextColor),
        ) ??
        defaultTextStyle.copyWith(
          font: font,
          decoration: pw.TextDecoration.combine(<pw.TextDecoration>[
            if (strike) pw.TextDecoration.lineThrough,
            if (underline) pw.TextDecoration.underline,
          ]),
          decorationStyle: pw.TextDecorationStyle.solid,
          decorationColor: textColor ?? backgroundTextColor,
          fontBold: await onRequestBoldFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontItalic: await onRequestItalicFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontBoldItalic: await onRequestBothFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontFallback: fonts,
          fontSize: !addFontSize ? null : fontSize ?? defaultFontSize.toDouble(),
          lineSpacing: lineSpacing,
          color: textColor,
          background: pw.BoxDecoration(color: backgroundTextColor),
        );
    spans.add(pw.TextSpan(text: content, style: decided_style));
    if (returnContentIfNeedIt && spans.isEmpty) {
      return <pw.TextSpan>[pw.TextSpan(text: line.data.toString(), style: style ?? decided_style)];
    }
    return spans;
  }

  @override
  Future<pw.Widget> getBlockQuote(List<pw.InlineSpan> spansToWrap, [pw.TextStyle? style]) async {
    final pw.TextStyle defaultStyle = pw.TextStyle(color: PdfColor.fromHex("#808080"), lineSpacing: 6.5);
    final pw.TextStyle blockquoteStyle = blockQuoteTextStyle ?? defaultStyle;
    final pw.Container widget = pw.Container(
      width: pageWidth,
      padding: const pw.EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
      decoration: pw.BoxDecoration(
        color: this.blockQuoteBackgroundColor ?? PdfColor.fromHex('#fbfbf9'),
        border: pw.Border(
          left: pw.BorderSide(
            color: blockQuoteDividerColor ?? PdfColors.blue,
            width: blockQuotethicknessDividerColor ?? 2.5,
          ),
        ),
      ),
      child: pw.RichText(
        softWrap: true,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          style: blockquoteStyle,
          children: <pw.InlineSpan>[...spansToWrap],
        ),
      ),
    );
    return widget;
  }

  @override
  Future<pw.Widget> getCodeBlock(List<pw.InlineSpan> spansToWrap, [pw.TextStyle? style]) async {
    final pw.TextStyle defaultCodeBlockStyle = pw.TextStyle(
      fontSize: 12,
      font: codeBlockFont ?? pw.Font.courier(),
      fontFallback: <pw.Font>[
        pw.Font.courierBold(),
        pw.Font.courierBoldOblique(),
        pw.Font.courierOblique(),
        pw.Font.symbol()
      ],
      letterSpacing: 1.5,
      lineSpacing: 1.1,
      wordSpacing: 0.5,
      color: PdfColor.fromHex("#808080"),
    );
    final pw.TextStyle codeBlockStyle = codeBlockTextStyle ?? defaultCodeBlockStyle;
    final pw.Widget widget = pw.Container(
      width: pageWidth,
      color: this.codeBlockBackgroundColor ?? PdfColor.fromHex('#fbfbf9'),
      padding: const pw.EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
      child: pw.RichText(
        softWrap: true,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          style: codeBlockStyle,
          children: <pw.InlineSpan>[
            pw.TextSpan(text: "$numCodeLine", style: codeBlockNumLinesTextStyle),
            const pw.TextSpan(text: "  "),
            ...spansToWrap,
          ],
        ),
      ),
    );
    return widget;
  }

  @override
  Future<List<pw.TextSpan>> getLinkStyle(Line line, [pw.TextStyle? style, bool addFontSize = true]) async {
    final List<pw.TextSpan> spans = <pw.TextSpan>[];
    final double? fontSize = double.tryParse(line.attributes?['size']);
    final double? lineHeight = line.attributes?['line-height'];
    final String? fontFamily = line.attributes?['font'];
    final PdfColor? textColor = pdfColorString(line.attributes?['color']);
    final PdfColor? backgroundTextColor = pdfColorString(line.attributes?['background']);
    final double? lineSpacing = lineHeight?.resolveLineHeight();
    final bool bold = line.attributes?['bold'] ?? false;
    final bool italic = line.attributes?['italic'] ?? false;
    final bool strike = line.attributes?['strike'] ?? false;
    final bool underline = line.attributes?['underline'] ?? false;
    final String href = line.attributes!['link'];
    final String hrefContent = line.data as String;
    final pw.Font font = await onRequestFont.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY);
    final List<pw.Font> fonts =
        await onRequestFallbacks?.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY) ?? <pw.Font>[];
    spans.add(
      pw.TextSpan(
        annotation: pw.AnnotationLink(href),
        text: hrefContent,
        style: (style ?? defaultTextStyle).copyWith(
          color: textColor ?? defaultLinkColor,
          background: backgroundTextColor == null ? null : pw.BoxDecoration(color: backgroundTextColor),
          fontStyle: italic ? pw.FontStyle.italic : null,
          fontWeight: bold ? pw.FontWeight.bold : null,
          decoration: pw.TextDecoration.combine(<pw.TextDecoration>[
            if (strike) pw.TextDecoration.lineThrough,
            if (underline) pw.TextDecoration.underline,
          ]),
          decorationStyle: pw.TextDecorationStyle.solid,
          decorationColor: defaultLinkColor,
          font: font,
          fontBold: await onRequestBoldFont?.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontItalic: await onRequestItalicFont?.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontBoldItalic: await onRequestBothFont?.call(fontFamily ?? Constant.DEFAULT_FONT_FAMILY),
          fontFallback: fonts,
          fontSize: !addFontSize ? null : fontSize ?? defaultFontSize.toDouble(),
          lineSpacing: lineSpacing,
        ),
      ),
    );
    return spans;
  }

  @override
  Future<pw.Widget> getHeaderBlock(List<pw.InlineSpan> spansToWrap, int headerLevel, int indentLevel,
      [pw.TextStyle? style]) async {
    final double defaultFontSize = headerLevel.resolveHeaderLevel();
    final pw.TextStyle textStyle =
        style?.copyWith(fontSize: defaultFontSize) ?? defaultTextStyle.copyWith(fontSize: defaultFontSize);
    return pw.Container(
        padding: pw.EdgeInsets.only(left: indentLevel.toDouble() * 7, top: 3, bottom: 3.5),
        child: pw.RichText(
          softWrap: true,
          overflow: pw.TextOverflow.span,
          text: pw.TextSpan(
            style: textStyle,
            children: spansToWrap,
          ),
        ));
  }

  @override
  Future<pw.Widget> getAlignedHeaderBlock(
    List<pw.InlineSpan> spansToWrap,
    int headerLevel,
    String align,
    int indentLevel, [
    pw.TextStyle? style,
  ]) async {
    final String alignment = align;
    final pw.Alignment al = alignment.resolvePdfBlockAlign;
    final pw.TextAlign textAlign = alignment.resolvePdfTextAlign;
    final double spacing = (spansToWrap.firstOrNull?.style?.lineSpacing ?? 1.0);
    return pw.Container(
      padding: pw.EdgeInsets.only(left: indentLevel * 7, top: 3, bottom: spacing.resolvePaddingByLineHeight()),
      alignment: al,
      child: pw.RichText(
        textAlign: textAlign,
        softWrap: true,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(children: spansToWrap),
      ),
    );
  }

  @override
  Future<pw.Widget> getAlignedParagraphBlock(
    List<pw.InlineSpan> spansToWrap,
    String align,
    int indentLevel, [
    pw.TextStyle? style,
  ]) async {
    final double spacing = (spansToWrap.firstOrNull?.style?.lineSpacing ?? 1.0);
    return pw.Container(
      alignment: align.resolvePdfBlockAlign,
      padding: pw.EdgeInsets.only(left: indentLevel * 7, bottom: spacing.resolvePaddingByLineHeight()),
      child: pw.RichText(
        textAlign: align.resolvePdfTextAlign,
        softWrap: true,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          children: spansToWrap,
        ),
      ),
    );
  }

  @override
  Future<pw.Widget> getListBlock(
    List<pw.InlineSpan> spansToWrap,
    String listType,
    String align,
    int indentLevel, [
    pw.TextStyle? style,
  ]) async {
    late final pw.WidgetSpan widgets;
    final double? spacing = (spansToWrap.firstOrNull?.style?.lineSpacing);
    if (listType != 'uncheked' && listType != 'checked') {
      final String typeList = listType == 'ordered' ? '$numberList.' : '•';
      //replace with bullet widget by error with fonts callback
      widgets = pw.WidgetSpan(
        child: pw.Container(
          padding: pw.EdgeInsets.only(
              left: indentLevel > 0 ? indentLevel * 7 : 15, bottom: spacing?.resolvePaddingByLineHeight() ?? 1.5),
          child: pw.RichText(
            softWrap: true,
            textAlign: align.resolvePdfTextAlign,
            overflow: pw.TextOverflow.span,
            text: pw.TextSpan(
              text: '$typeList ',
              children: <pw.InlineSpan>[
                pw.TextSpan(children: spansToWrap),
              ],
            ),
          ),
        ),
      );
    }
    if (listType == 'checked' || listType == 'unchecked') {
      widgets = pw.WidgetSpan(
        child: pw.Container(
          padding: pw.EdgeInsets.only(
              left: indentLevel > 0 ? indentLevel * 7 : 15, bottom: spacing?.resolvePaddingByLineHeight() ?? 1.5),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Checkbox(
                activeColor: PdfColors.blue400,
                name: 'check ${Random.secure().nextInt(9999999) + 50}',
                value: listType == 'checked' ? true : false,
              ),
              pw.Expanded(
                child: pw.RichText(
                  textAlign: align.resolvePdfTextAlign,
                  softWrap: true,
                  overflow: pw.TextOverflow.span,
                  text: pw.TextSpan(
                    children: <pw.InlineSpan>[
                      pw.TextSpan(children: <pw.InlineSpan>[...spansToWrap])
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pw.Container(
      padding: pw.EdgeInsets.only(
        left: indentLevel > 0 ? indentLevel * 7 : 15,
        bottom: spacing?.resolvePaddingByLineHeight() ?? 1.5,
      ),
      child: pw.RichText(
        softWrap: true,
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          children: <pw.InlineSpan>[
            widgets,
          ],
        ),
      ),
    );
  }
}
