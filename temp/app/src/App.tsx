import { useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import type { Variants } from 'framer-motion';
import type { OnboardingState } from '@/types/onboarding';

// Pages
import WelcomePage from '@/pages/WelcomePage';
import FeatureCalendarPage from '@/pages/FeatureCalendarPage';
import FeatureFocusPage from '@/pages/FeatureFocusPage';
import PersonalizationPage from '@/pages/PersonalizationPage';
import KickstarterPage from '@/pages/KickstarterPage';
import TextAnimationPage from '@/pages/TextAnimationPage';
import QuestionnairePage from '@/pages/QuestionnairePage';
import SignUpPage from '@/pages/SignUpPage';

const pageVariants: Variants = {
  initial: (direction: number) => ({
    x: direction > 0 ? '100%' : '-100%',
    opacity: 0,
  }),
  animate: {
    x: 0,
    opacity: 1,
    transition: {
      x: { type: 'spring' as const, stiffness: 300, damping: 30 },
      opacity: { duration: 0.2 },
    },
  },
  exit: (direction: number) => ({
    x: direction > 0 ? '-100%' : '100%',
    opacity: 0,
    transition: {
      x: { type: 'spring' as const, stiffness: 300, damping: 30 },
      opacity: { duration: 0.2 },
    },
  }),
};

function App() {
  const [currentPage, setCurrentPage] = useState(0);
  const [direction, setDirection] = useState(0);
  const [state, setState] = useState<OnboardingState>({
    currentPage: 0,
    answers: {},
  });

  const handleNext = () => {
    setDirection(1);
    setCurrentPage((prev) => prev + 1);
    setState((prev) => ({ ...prev, currentPage: currentPage + 1 }));
  };

  const handleBack = () => {
    if (currentPage > 0) {
      setDirection(-1);
      setCurrentPage((prev) => prev - 1);
      setState((prev) => ({ ...prev, currentPage: currentPage - 1 }));
    }
  };

  const renderPage = () => {
    const commonProps = {
      onNext: handleNext,
      onBack: handleBack,
      state,
      setState,
    };

    switch (currentPage) {
      case 0:
        return <WelcomePage {...commonProps} />;
      case 1:
        return <FeatureCalendarPage {...commonProps} />;
      case 2:
        return <FeatureFocusPage {...commonProps} />;
      case 3:
        return <PersonalizationPage {...commonProps} />;
      case 4:
        return <KickstarterPage {...commonProps} />;
      case 5:
        return <TextAnimationPage {...commonProps} />;
      case 6:
      case 7:
      case 8:
      case 9:
      case 10:
      case 11:
      case 12:
      case 13:
        return <QuestionnairePage {...commonProps} questionIndex={currentPage - 6} />;
      case 14:
        return <SignUpPage {...commonProps} />;
      default:
        return <WelcomePage {...commonProps} />;
    }
  };

  return (
    <div className="min-h-screen bg-gray-100 flex items-center justify-center">
      <div className="mobile-frame bg-white w-full max-w-[430px] h-screen max-h-[932px] relative overflow-hidden">
        <AnimatePresence mode="wait" custom={direction}>
          <motion.div
            key={currentPage}
            custom={direction}
            variants={pageVariants}
            initial="initial"
            animate="animate"
            exit="exit"
            className="absolute inset-0"
          >
            {renderPage()}
          </motion.div>
        </AnimatePresence>

        {/* Page Indicator (for debugging) */}
        <div className="absolute bottom-1 left-1/2 -translate-x-1/2 flex gap-1 z-50">
          <span className="text-[10px] text-gray-400 bg-white/80 px-2 py-0.5 rounded-full">
            {currentPage + 1} / 15
          </span>
        </div>
      </div>
    </div>
  );
}

export default App;
