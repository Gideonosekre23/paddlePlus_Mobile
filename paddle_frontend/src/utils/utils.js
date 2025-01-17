const saveToLocalStorage = (data) => {
    Object.keys(data).forEach((key) => {
      localStorage.setItem(key, data[key]);
    });
};

export default saveToLocalStorage;
  