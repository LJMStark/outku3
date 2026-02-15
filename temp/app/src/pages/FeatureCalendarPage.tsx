import { motion } from 'framer-motion';
import { Volume2, VolumeX, ArrowDown, ChevronRight } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';
import { useState } from 'react';

const dialogBoxes = [
  {
    text: 'You have a coffee chat with someone named Anna at 1:30 PM - enjoy!',
    style: 'bg-[#F5F5F0]',
  },
  {
    text: 'Coffee with Anna! Maybe meet at the new spot we tried yesterday? ☕',
    style: 'bg-[#E8D5C4] border-2 border-[#D4A574]',
  },
  {
    text: 'Been a while since you hung out with Anna - schedule a hang? 👀',
    style: 'bg-[#2D2D3A] text-white',
  },
];

export default function FeatureCalendarPage({ onNext }: PageProps) {
  const [soundEnabled, setSoundEnabled] = useState(true);

  return (
    <div className="h-full flex flex-col bg-[#0D8A6A] relative overflow-hidden">
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

      {/* Speaker Toggle */}
      <button
        onClick={() => setSoundEnabled(!soundEnabled)}
        className="absolute top-14 left-4 w-10 h-10 rounded-full bg-white/20 flex items-center justify-center backdrop-blur-sm z-10"
      >
        {soundEnabled ? (
          <Volume2 className="w-5 h-5 text-white" />
        ) : (
          <VolumeX className="w-5 h-5 text-white" />
        )}
      </button>

      {/* Progress Dots */}
      <div className="flex justify-center gap-2 mt-2">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className={`h-1 rounded-full transition-all duration-300 ${
              i === 0 ? 'w-8 bg-white' : 'w-8 bg-white/30'
            }`}
          />
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-8">
        {/* Title */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="text-3xl font-bold text-white text-center mb-2"
        >
          Not Just a Calendar <span className="text-2xl">😄</span>
        </motion.h1>
        <motion.p
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-white/80 text-center mb-8"
        >
          Inku learns and grows with you
        </motion.p>

        {/* Dialog Boxes */}
        <div className="flex-1 flex flex-col items-center gap-4">
          {dialogBoxes.map((box, index) => (
            <motion.div
              key={index}
              initial={{ x: index % 2 === 0 ? -50 : 50, opacity: 0 }}
              animate={{ x: 0, opacity: 1 }}
              transition={{ delay: 0.2 + index * 0.2, duration: 0.5 }}
              className="w-full max-w-sm"
            >
              <div
                className={`${box.style} rounded-2xl p-4 shadow-lg text-sm leading-relaxed`}
              >
                {box.text}
              </div>
              {index < dialogBoxes.length - 1 && (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.5 + index * 0.2 }}
                  className="flex justify-center my-2"
                >
                  <ArrowDown className="w-6 h-6 text-white/60 animate-bounce" />
                </motion.div>
              )}
            </motion.div>
          ))}
        </div>

        {/* Character */}
        <motion.div
          initial={{ x: -50, opacity: 0 }}
          animate={{ x: 0, opacity: 1 }}
          transition={{ delay: 0.8 }}
          className="absolute bottom-24 left-4"
        >
          <motion.img
            src="/characters/inku-main.png"
            alt="Inku"
            className="w-20 h-20 object-contain"
            animate={{ y: [0, -4, 0] }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          />
        </motion.div>
      </div>

      {/* CTA Button */}
      <div className="px-6 pb-8">
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 1 }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onNext}
          className="w-full bg-[#1A1A2E] text-white py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2"
        >
          Continue <span className="text-xl">👋</span>
          <ChevronRight className="w-5 h-5" />
        </motion.button>
      </div>
    </div>
  );
}
