import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Volume2, VolumeX, ChevronRight } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';

export default function FeatureFocusPage({ onNext }: PageProps) {
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [showAfter, setShowAfter] = useState(false);

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
              i === 1 ? 'w-8 bg-white' : 'w-8 bg-white/30'
            }`}
          />
        ))}
      </div>

      {/* Blue Monster Character */}
      <motion.div
        initial={{ y: -50, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        className="absolute top-20 right-4"
      >
        <motion.img
          src="/characters/blue-monster.png"
          alt="Focus Monster"
          className="w-20 h-20 object-contain"
          animate={{ y: [0, -6, 0] }}
          transition={{ duration: 2.5, repeat: Infinity, ease: 'easeInOut' }}
        />
      </motion.div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-8">
        {/* Title */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="text-3xl font-bold text-white text-center mb-2"
        >
          Focus, not frenzy <span className="text-2xl">✨</span>
        </motion.h1>
        <motion.p
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="text-white/80 text-center mb-8"
        >
          Widget updates quietly—no dings, no FOMO.
        </motion.p>

        {/* Before/After Card */}
        <motion.div
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="flex-1 flex flex-col items-center"
        >
          <div 
            className="w-full max-w-sm bg-white rounded-3xl overflow-hidden shadow-2xl cursor-pointer"
            onClick={() => setShowAfter(!showAfter)}
          >
            <AnimatePresence mode="wait">
              {!showAfter ? (
                <motion.div
                  key="before"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="p-6"
                >
                  <div className="space-y-2">
                    {[...Array(8)].map((_, i) => (
                      <div
                        key={i}
                        className="h-3 bg-gray-200 rounded"
                        style={{ 
                          width: `${60 + Math.random() * 40}%`,
                          filter: 'blur(2px)'
                        }}
                      />
                    ))}
                  </div>
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ delay: 0.5, type: 'spring' }}
                    className="mt-4 text-center"
                  >
                    <span className="inline-block bg-red-500 text-white px-4 py-2 rounded-full text-sm font-bold transform -rotate-6">
                      HEEEELP!
                    </span>
                  </motion.div>
                  <div className="mt-4 text-center">
                    <span className="inline-block bg-red-500 text-white px-6 py-2 rounded-full text-sm font-bold">
                      BEFORE
                    </span>
                  </div>
                </motion.div>
              ) : (
                <motion.div
                  key="after"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="p-6"
                >
                  <div className="bg-[#F5F5F0] rounded-2xl p-4">
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 bg-[#0D8A6A] rounded-full flex items-center justify-center flex-shrink-0">
                        <span className="text-white text-lg">🏭</span>
                      </div>
                      <div>
                        <h3 className="font-bold text-[#1A1A2E]">2:30 Inku Factory Sync</h3>
                        <p className="text-sm text-gray-600 mt-1">
                          <strong>With:</strong> You, Britt and 3 others.
                        </p>
                        <p className="text-sm text-gray-500 mt-2">
                          Meeting with Raymond at the factory. Call to discuss next steps in production. Your Factory rep was out on vacation. Ask how it was, and recap where the project is to start.
                        </p>
                      </div>
                    </div>
                  </div>
                  <div className="mt-4 text-center">
                    <span className="inline-block bg-[#0D8A6A] text-white px-6 py-2 rounded-full text-sm font-bold">
                      AFTER
                    </span>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          <p className="text-white/60 text-sm mt-4">Tap card to see the difference</p>
        </motion.div>
      </div>

      {/* CTA Button */}
      <div className="px-6 pb-8">
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.6 }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onNext}
          className="w-full bg-[#1A1A2E] text-white py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2"
        >
          I will Focus <span className="text-xl">🧘</span>
          <ChevronRight className="w-5 h-5" />
        </motion.button>
      </div>
    </div>
  );
}
