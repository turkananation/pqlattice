import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/components/github_button.dart';
import 'package:jaspr_content/components/sidebar_toggle_button.dart';
import 'package:jaspr_content/components/theme_toggle.dart';

/// Branded header for the pqlattice documentation site.
class SiteHeader extends StatelessComponent {
  /// Creates the site header.
  const SiteHeader({super.key});

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      Document.head(children: [Style(styles: _styles)]),
      header(classes: 'pql-header', [
        const SidebarToggleButton(),
        a(classes: 'pql-title', href: './', [
          img(src: 'images/logo.svg', alt: 'pqlattice logo'),
          span([Component.text('pqlattice')]),
        ]),
        nav(classes: 'pql-nav', [
          a(href: 'math', [Component.text('Math')]),
          a(href: 'measurements', [Component.text('Measurements')]),
          a(href: 'getting-started', [Component.text('Start')]),
          const ThemeToggle(),
          const GitHubButton(repo: 'turkananation/pqlattice'),
        ]),
      ]),
    ]);
  }

  static List<StyleRule> get _styles => [
    css('.pql-header', [
      css('&').styles(
        height: 4.rem,
        display: Display.flex,
        alignItems: AlignItems.center,
        gap: Gap.column(.875.rem),
        padding: Padding.symmetric(horizontal: 1.rem, vertical: .25.rem),
        margin: Margin.symmetric(horizontal: Unit.auto),
        border: Border.only(
          bottom: BorderSide(color: Color('#00000014'), width: 1.px),
        ),
        backgroundColor: Color(
          'color-mix(in srgb, var(--background) 88%, transparent)',
        ),
        raw: {'backdrop-filter': 'blur(14px)'},
      ),
      css.media(MediaQuery.all(minWidth: 768.px), [
        css('&').styles(padding: Padding.symmetric(horizontal: 2.5.rem)),
      ]),
      css('.pql-title', [
        css('&').styles(
          display: Display.inlineFlex,
          flex: Flex(basis: 18.rem),
          alignItems: AlignItems.center,
          gap: Gap.column(.75.rem),
          minWidth: Unit.zero,
        ),
        css('img').styles(height: 1.75.rem, width: 1.75.rem),
        css('span').styles(
          fontWeight: FontWeight.w800,
          letterSpacing: Unit.zero,
          whiteSpace: WhiteSpace.noWrap,
        ),
      ]),
      css('.pql-nav', [
        css('&').styles(
          display: Display.flex,
          flex: Flex(grow: 1),
          alignItems: AlignItems.center,
          justifyContent: JustifyContent.end,
          gap: Gap.column(.35.rem),
          overflow: Overflow.hidden,
        ),
        css('> a').styles(
          display: Display.none,
          padding: Padding.symmetric(horizontal: .7.rem, vertical: .45.rem),
          radius: BorderRadius.circular(.375.rem),
          fontSize: .875.rem,
          fontWeight: FontWeight.w600,
        ),
        css('> a:hover').styles(backgroundColor: Color('#0000000d')),
        css.media(MediaQuery.all(minWidth: 760.px), [
          css('> a').styles(display: Display.inlineFlex),
        ]),
      ]),
    ]),
  ];
}
