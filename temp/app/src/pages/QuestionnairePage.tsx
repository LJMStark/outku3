import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronLeft, Check, ChevronRight } from 'lucide-react';
import type { PageProps } from '@/types/onboarding';
import { allQuestions } from '@/data/questions';
import * as Icons from 'lucide-react';

interface QuestionnairePageProps extends PageProps {
  questionIndex: number;
}

export default function QuestionnairePage({ 
  onNext, 
  onBack, 
  state, 
  setState, 
  questionIndex 
}: QuestionnairePageProps) {
  const question = allQuestions[questionIndex];
  const isLastQuestion = questionIndex === allQuestions.length - 1;
  
  const currentAnswer = state.answers[question.id as keyof typeof state.answers];
  const [selectedOptions, setSelectedOptions] = useState<string[]>(
    Array.isArray(currentAnswer) ? currentAnswer : currentAnswer ? [currentAnswer] : []
  );

  const handleSelect = (optionId: string) => {
    if (question.type === 'single') {
      setSelectedOptions([optionId]);
    } else {
      setSelectedOptions(prev => 
        prev.includes(optionId)
          ? prev.filter(id => id !== optionId)
          : [...prev, optionId]
      );
    }
  };

  const handleContinue = () => {
    setState(prev => ({
      ...prev,
      answers: {
        ...prev.answers,
        [question.id]: question.type === 'single' ? selectedOptions[0] : selectedOptions,
      },
    }));
    onNext();
  };

  const getIcon = (iconName: string) => {
    const Icon = (Icons as unknown as Record<string, React.ComponentType<{ className?: string }>>)[iconName];
    return Icon ? <Icon className="w-5 h-5" /> : null;
  };

  return (
    <div className="h-full flex flex-col bg-white relative overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-4 px-4 pt-3 pb-2">
        <button
          onClick={onBack}
          className="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center"
        >
          <ChevronLeft className="w-5 h-5 text-gray-600" />
        </button>
        <div className="flex-1">
          <p className="text-xs text-[#0D8A6A] font-medium">
            {questionIndex < 2 ? 'Profile' : questionIndex < 5 ? 'Habits & Goals' : 'Personalization'}
          </p>
          {/* Progress Bar */}
          <div className="flex gap-1 mt-1">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className={`h-1 flex-1 rounded-full ${
                  i <= Math.floor(questionIndex / 3) ? 'bg-[#0D8A6A]' : 'bg-gray-200'
                }`}
              />
            ))}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex flex-col px-6 pt-4 overflow-y-auto">
        {/* Question */}
        <motion.h1
          initial={{ y: -20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          className="text-2xl font-bold text-[#1A1A2E] mb-2"
        >
          {question.title}
        </motion.h1>
        {question.subtitle && (
          <motion.p
            initial={{ y: -10, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: 0.1 }}
            className="text-gray-500 text-sm mb-6"
          >
            {question.subtitle}
          </motion.p>
        )}

        {/* Options */}
        <div className="flex-1 space-y-3">
          <AnimatePresence>
            {question.options.map((option, index) => {
              const isSelected = selectedOptions.includes(option.id);
              
              return (
                <motion.button
                  key={option.id}
                  initial={{ x: -20, opacity: 0 }}
                  animate={{ x: 0, opacity: 1 }}
                  transition={{ delay: index * 0.05 }}
                  whileHover={{ scale: 1.01 }}
                  whileTap={{ scale: 0.99 }}
                  onClick={() => handleSelect(option.id)}
                  className={`w-full flex items-center gap-4 p-4 rounded-2xl border-2 transition-all ${
                    isSelected
                      ? 'border-[#0D8A6A] bg-[#F0FDF9]'
                      : 'border-gray-200 bg-white hover:border-gray-300'
                  }`}
                >
                  {option.emoji ? (
                    <span className="text-2xl">{option.emoji}</span>
                  ) : option.icon ? (
                    <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                      isSelected ? 'bg-[#0D8A6A]' : 'bg-gray-100'
                    }`}>
                      <div className={isSelected ? 'text-white' : 'text-gray-600'}>
                        {getIcon(option.icon)}
                      </div>
                    </div>
                  ) : null}
                  <span className={`flex-1 text-left font-medium ${
                    isSelected ? 'text-[#0D8A6A]' : 'text-[#1A1A2E]'
                  }`}>
                    {option.label}
                  </span>
                  {isSelected && (
                    <motion.div
                      initial={{ scale: 0 }}
                      animate={{ scale: 1 }}
                      className="w-6 h-6 rounded-full bg-[#0D8A6A] flex items-center justify-center"
                    >
                      <Check className="w-4 h-4 text-white" />
                    </motion.div>
                  )}
                </motion.button>
              );
            })}
          </AnimatePresence>
        </div>

        {/* Character */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="flex items-end gap-3 mt-6"
        >
          <motion.img
            src="/characters/inku-main.png"
            alt="Inku"
            className="w-16 h-16 object-contain"
            animate={{ y: [0, -4, 0] }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          />
          <div className="flex-1 bg-gray-100 rounded-2xl p-3 relative">
            <div className="absolute -left-2 bottom-4 w-0 h-0 border-t-6 border-t-transparent border-r-6 border-r-gray-100 border-b-6 border-b-transparent" />
            <p className="text-gray-600 text-sm">
              {selectedOptions.length > 0 
                ? question.type === 'single' 
                  ? "Perfect — I'll make sure to keep that in mind."
                  : "I'll wait for your choice!"
                : "I'll wait for your choice!"}
            </p>
          </div>
        </motion.div>
      </div>

      {/* CTA Button */}
      <div className="px-6 pb-8 pt-4">
        <motion.button
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.4 }}
          whileHover={{ scale: selectedOptions.length > 0 ? 1.02 : 1 }}
          whileTap={{ scale: selectedOptions.length > 0 ? 0.98 : 1 }}
          onClick={handleContinue}
          disabled={selectedOptions.length === 0}
          className={`w-full py-4 rounded-full font-semibold text-lg shadow-lg flex items-center justify-center gap-2 transition-all ${
            selectedOptions.length > 0
              ? 'bg-[#0D8A6A] text-white'
              : 'bg-gray-200 text-gray-400 cursor-not-allowed'
          }`}
        >
          {isLastQuestion ? 'Continue' : 'Continue'}
          <ChevronRight className="w-5 h-5" />
        </motion.button>
      </div>
    </div>
  );
}
