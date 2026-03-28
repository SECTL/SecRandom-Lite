enum ResponsiveScreenState { large, portrait, short, small }

class ResponsiveLayoutDecisionInput {
  const ResponsiveLayoutDecisionInput({
    required this.contentWidth,
    required this.contentHeight,
    required this.largeResultWidth,
    required this.largePanelTop,
    required this.contentTop,
    required this.portraitResultHeight,
    required this.shortResultWidth,
  });

  final double contentWidth;
  final double contentHeight;
  final double largeResultWidth;
  final double largePanelTop;
  final double contentTop;
  final double portraitResultHeight;
  final double shortResultWidth;
}

ResponsiveScreenState decideResponsiveScreenState(
  ResponsiveLayoutDecisionInput input, {
  double epsilon = 0.5,
}) {
  ResponsiveScreenState state = ResponsiveScreenState.large;

  final largeWidthRatio = _safeRatio(
    input.largeResultWidth,
    input.contentWidth,
  );
  final largePanelOverflow = input.largePanelTop <= input.contentTop + epsilon;

  if (largeWidthRatio < 0.5 - epsilonRatio(input.contentWidth, epsilon)) {
    state = ResponsiveScreenState.portrait;
  } else if (largePanelOverflow) {
    state = ResponsiveScreenState.short;
  }

  if (state == ResponsiveScreenState.portrait) {
    final portraitHeightRatio = _safeRatio(
      input.portraitResultHeight,
      input.contentHeight,
    );
    if (portraitHeightRatio <
        0.25 - epsilonRatio(input.contentHeight, epsilon)) {
      return ResponsiveScreenState.small;
    }
  }

  if (state == ResponsiveScreenState.short) {
    final shortWidthRatio = _safeRatio(
      input.shortResultWidth,
      input.contentWidth,
    );
    if (shortWidthRatio < 0.5 - epsilonRatio(input.contentWidth, epsilon)) {
      return ResponsiveScreenState.small;
    }
  }

  return state;
}

double _safeRatio(double value, double total) {
  if (total <= 0) {
    return 0;
  }
  return value / total;
}

double epsilonRatio(double total, double epsilon) {
  if (total <= 0) {
    return 0;
  }
  return epsilon / total;
}
