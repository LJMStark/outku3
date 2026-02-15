import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import type { PageProps } from '@/types/onboarding';

const textLines = [
  { text: 'Time is all that matters.', align: 'left' as const },
  { text: 'But it never feels enough.', align: 'left' as const },
  { text: 'And somehow,', align: 'right' as const },
  { text: 'still...it wastes away.', align: 'right' as const },
  { text: 'Distractions everywhere', align: 'left' as const },
  { text: 'Control nowhere.', align: 'left' as const },
  { text: 'More tools = More noise', align: 'center' as const },
];

const finalLines = [
  { text: 'Inku is different.', highlight: true },
  { text: 'Giving you back what\'s yours.', highlight: true },
];

const features = [
  { emoji: '💡', text: 'Clarity' },
  { emoji: '🎛️', text: 'Control' },
  { emoji: '❤️', text: 'Joy' },
];

export default function TextAnimationPage({ onNext }: PageProps) {
  const [visibleLines, setVisibleLines] = useState(0);
  const [showFinal, setShowFinal] = useState(false);
  const [showFeatures, setShowFeatures] = useState(false);
  const [canTap, setCanTap] = useState(false);

  useEffect(() => {
    const timer = setInterval(() => {
      setVisibleLines((prev) => {
        if (prev >= textLines.length) {
          clearInterval(timer);
          setTimeout(() => setShowFinal(true), 300);
          setTimeout(() => setShowFeatures(true), 800);
          setTimeout(() => setCanTap(true), 1500);
          return prev;
        }
        return prev + 1;
      });
    }, 400);

    return () => clearInterval(timer);
  }, []);

  const handleTap = () => {
    if (canTap) {
      onNext();
    }
  };

  return (
    <div 
      className="h-full flex flex-col bg-[#1A1A2E] relative overflow-hidden cursor-pointer"
      onClick={handleTap}
    >
      {/* Status Bar */}
      <div className="flex items-center justify-between px-6 pt-3 pb-2">
        <span className="text-white text-sm font-semibold">22:30</span>
        <div className="flex items-center gap-1">
          <div className="flex gap-0.5">
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white rounded-sm" />
            <div className="w-1 h-3 bg-white/40 rounded-sm" />
          </div>
          <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 3C7.46 3 3.34 4.78.29 7.67c-.18.18-.29.43-.29.71 0 .28.11.53.29.71l11 11c.39.39 1.02.39 1.41 0l11-11c.18-.18.29-.43.29-.71 0-.28-.11-.53-.29-.71C20.66 4.78 16.54 3 12 3z"/>
          </svg>
          <div className="flex items-center gap-1 bg-white/20 rounded-md px-1.5 py-0.5">
            <span className="text-white text-xs font-semibold">98</span>
          </div>
        </div>
      </div>

      {/* Skip Button */}
      <button
        onClick={(e) => {
          e.stopPropagation();
          onNext();
        }}
        className="absolute top-14 right-4 px-4 py-2 bg-white/10 rounded-full text-white/60 text-sm"
      >
        Skip
      </button>

      {/* Content */}
      <div className="flex-1 flex flex-col px-8 pt-12">
        {/* Animated Text Lines */}
        <div className="flex-1">
          {textLines.map((line, index) => (
            <motion.p
              key={index}
              initial={{ opacity: 0, y: 20 }}
              animate={visibleLines > index ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.4 }}
              className={`text-white text-2xl font-bold mb-4 ${
                line.align === 'right' ? 'text-right' : 
                line.align === 'center' ? 'text-center' : 'text-left'
              }`}
            >
              {line.text}
            </motion.p>
          ))}

          {/* Final Lines with Highlight */}
          {showFinal && finalLines.map((line, index) => (
            <motion.div
              key={`final-${index}`}
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: index * 0.2 }}
              className="flex justify-center mb-3"
            >
              <span className="bg-white text-[#1A1A2E] px-4 py-2 rounded-full text-xl font-bold">
                {line.text}
              </span>
            </motion.div>
          ))}

          {/* Features */}
          {showFeatures && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 0.3 }}
              className="flex flex-col items-center gap-3 mt-6"
            >
              {features.map((feature, index) => (
                <motion.div
                  key={feature.text}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.5 + index * 0.15 }}
                  className="flex items-center gap-2"
                >
                  <span className="text-2xl">{feature.emoji}</span>
                  <span className="text-white text-xl font-semibold">{feature.text}</span>
                </motion.div>
              ))}
            </motion.div>
          )}
        </div>

        {/* Tap to Continue */}
        {canTap && (
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="text-white/40 text-sm text-center pb-8"
          >
            (Tap Anywhere To Continue)
          </motion.p>
        )}
      </div>
    </div>
  );
}
