import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../providers/onboarding_provider.dart';
import 'onboarding_art.dart';

/// Onboarding (3 écrans) — affiché UNE SEULE FOIS après installation,
/// avant la connexion. Dégradé panneau deepGreenLight → deepGreenDark,
/// rayon 32, bouton principal unique. Responsive : téléphone portrait,
/// téléphone paysage (mise en page côte à côte) et tablettes/grands écrans
/// (contenu centré, largeur plafonnée).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPageData(
      title: 'Notez vos dépenses en quelques secondes',
      body: 'Ajoutez une dépense ou un revenu, et voyez tout de suite combien il vous reste.',
    ),
    _OnboardingPageData(
      title: 'Gardez le contrôle de votre budget',
      body: "Fixez des budgets par catégorie, suivez vos objectifs d'épargne et repartez à zéro chaque mois.",
    ),
    _OnboardingPageData(
      title: 'Disponible même sans internet',
      body: 'Notez vos opérations hors-ligne : tout se synchronise dès que le réseau revient, et vos données restent privées.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _complete(String route) {
    // Marque « onboarding vu » (les ouvertures suivantes n'affichent jamais cet écran).
    ref.read(onboardingSeenProvider.notifier).markSeen();
    if (mounted) context.go(route);
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final isLandscape = width > height && height < 540;
            final maxWidth = width >= 720 ? 560.0 : double.infinity;
            // Mise à l'échelle des textes selon la largeur disponible.
            final scale = (width / 400).clamp(0.8, 1.0);
            // Densité verticale (petits écrans : réduit les espacements).
            final vScale = (height / 620).clamp(0.75, 1.0);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: isLandscape
                        ? _landscapeLayout(scheme, height)
                        : _portraitLayout(scheme, height, scale, vScale),

                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Portrait téléphone / tablette (contenu centré et plafonné ≥ 720 px).
  /// Les espacements verticaux se réduisent sur les petits écrans (`vScale`)
  /// pour que le bouton principal reste visible sans défiler.
  Widget _portraitLayout(ColorScheme scheme, double height, double scale, double vScale) {
    double g(double value) => value * vScale;

    final panelH = (height * 0.30).clamp(150.0, 372.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _headerRow(scheme, padded: true),
        _illustrationPanel(height: panelH),
        SizedBox(height: g(12)),
        _textBlock(scheme, scale),
        SizedBox(height: g(12)),
        _dots(scheme),
        SizedBox(height: g(12)),
        _mainButton(scheme),
        if (_isLast) _accountLink(scheme),
        SizedBox(height: g(10)),
      ],
    );
  }

  /// Paysage (téléphone peu haut) : illustration à gauche, textes et action à droite.
  /// Les textes et l'en-tête se mettent à l'échelle selon la hauteur disponible.
  Widget _landscapeLayout(ColorScheme scheme, double height) {
    final panelH = (height * 0.76).clamp(190.0, 372.0);
    final textScale = (height / 470).clamp(0.78, 1.0);
    double g(double value) => value * ((height / 420).clamp(0.72, 1.0));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 16),
        _illustrationPanel(width: panelH * 0.92, height: panelH),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerRow(scheme, padded: false, height: 44),
                SizedBox(height: g(2)),
                _textBlock(scheme, textScale, alignEnd: true),
                SizedBox(height: g(12)),
                _dots(scheme, alignEnd: true),
                SizedBox(height: g(12)),
                _mainButton(scheme, padded: false),
                if (_isLast) Padding(padding: EdgeInsets.only(top: g(4)), child: _accountLink(scheme, alignEnd: true)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _headerRow(ColorScheme scheme, {required bool padded, double height = 56}) {
    return Container(
      height: height,
      padding: padded ? const EdgeInsets.symmetric(horizontal: 20) : EdgeInsets.zero,
      child: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'MyBudget',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          const Spacer(),
          if (!_isLast)
            TextButton(
              onPressed: () => _complete('/register'),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: const Text('Passer'),
            ),
        ],
      ),
    );
  }

  /// Panneau d'illustration (dégradé, rayon 32). S'adapte au cadre obtenu :
  /// sa largeur/hauteur est passée par le parent.
  Widget _illustrationPanel({double? width, required double height}) {
    return Container(
      width: width,
      height: height,
      margin: width == null ? const EdgeInsets.symmetric(horizontal: 20) : EdgeInsets.zero,
      decoration: const BoxDecoration(
        gradient: panelGradient,
        borderRadius: BorderRadius.all(Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x403869A1),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        child: PageView(
          controller: _pageController,
          onPageChanged: (page) => setState(() => _page = page),
          children: const [
            OnboardingIllustration(page: 0),
            OnboardingIllustration(page: 1),
            OnboardingIllustration(page: 2),
          ],
        ),
      ),
    );
  }

  /// Titre + corps, synchronisés avec la page courante. Mise à l'échelle
  /// selon la largeur (`scale`) pour ne jamais déborder, même à 320 px.
  Widget _textBlock(ColorScheme scheme, double scale, {bool alignEnd = false}) {
    final titleSize = (30 * scale).clamp(22.0, 30.0);
    final bodySize = (16 * scale).clamp(13.0, 16.0);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Padding(
        key: ValueKey<int>(_page),
        padding: EdgeInsets.symmetric(horizontal: alignEnd ? 0 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: alignEnd ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(
              _pages[_page].title,
              textAlign: alignEnd ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.5,
                color: scheme.onSurface,
              ),
            ),
            SizedBox(height: 8 * scale),
            Text(
              _pages[_page].body,
              textAlign: alignEnd ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                fontSize: bodySize,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Points de progression (page active allongée), tactiles (≥ 36 px).
  Widget _dots(ColorScheme scheme, {bool alignEnd = false}) {
    return Semantics(
      label: 'Page ${_page + 1} sur ${_pages.length}',
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _pages.length; i++)
            GestureDetector(
              onTap: () => _goToPage(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 32,
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: i == _page ? 26 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: i == _page ? scheme.primary : scheme.outline,
                    borderRadius: BorderRadius.circular(4.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Bouton principal (hauteur 56, rayon 18, largeur selon le conteneur).
  Widget _mainButton(ColorScheme scheme, {bool padded = true}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padded ? 20 : 0),
      child: Material(
        color: AppColors.deepGreenDark,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isLast ? () => _complete('/register') : _next,
          splashColor: Colors.white24,
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Center(
              child: Text(
                _isLast ? 'Commencer' : 'Suivant',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lien « J'ai déjà un compte » (page 3 uniquement).
  Widget _accountLink(ColorScheme scheme, {bool alignEnd = false}) {
    return Align(
      alignment: alignEnd ? Alignment.centerLeft : Alignment.center,
      child: TextButton(
        onPressed: () => _complete('/login'),
        style: TextButton.styleFrom(
          minimumSize: const Size(200, 44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: const Text("J'ai déjà un compte"),
      ),
    );
  }
}

/// Textes d'une page d'onboarding (aucune donnée — textes fixes).
class _OnboardingPageData {
  const _OnboardingPageData({required this.title, required this.body});

  final String title;
  final String body;
}
