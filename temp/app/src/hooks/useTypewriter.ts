import { useState, useEffect, useCallback } from 'react';

interface UseTypewriterOptions {
  text: string;
  speed?: number;
  delay?: number;
  onComplete?: () => void;
}

export function useTypewriter({
  text,
  speed = 30,
  delay = 0,
  onComplete,
}: UseTypewriterOptions) {
  const [displayText, setDisplayText] = useState('');
  const [isComplete, setIsComplete] = useState(false);
  const [isStarted, setIsStarted] = useState(false);

  const start = useCallback(() => {
    setIsStarted(true);
  }, []);

  const reset = useCallback(() => {
    setDisplayText('');
    setIsComplete(false);
    setIsStarted(false);
  }, []);

  useEffect(() => {
    if (!isStarted) return;

    let timeout: ReturnType<typeof setTimeout>;
    
    const typeNextChar = (index: number) => {
      if (index < text.length) {
        setDisplayText(text.slice(0, index + 1));
        timeout = setTimeout(() => typeNextChar(index + 1), speed);
      } else {
        setIsComplete(true);
        onComplete?.();
      }
    };

    timeout = setTimeout(() => typeNextChar(0), delay);

    return () => clearTimeout(timeout);
  }, [text, speed, delay, isStarted, onComplete]);

  return { displayText, isComplete, start, reset };
}
