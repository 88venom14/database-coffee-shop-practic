-- =====================================================================
-- Программные объекты базы данных coffee_shop_db
-- Дисциплина МДК.11.01 - Технология разработки и защиты баз данных
-- Курсовой проект "Разработка базы данных для кофейни"
-- Кодировка: UTF-8
--
-- Выполнять после создания таблиц (dump-coffee-shop.sql).
-- Содержит: представление, пользовательскую функцию, триггер,
-- хранимую процедуру (транзакция + переменные + условие + обработчик
-- исключений) и роли доступа.
-- =====================================================================

USE coffee_shop_db;

-- ---------------------------------------------------------------------
-- 1. Представление (VIEW): витрина заказов с именами клиентов
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_summary;
CREATE VIEW v_order_summary AS
SELECT o.OrderID,
       c.FullName  AS Customer,
       o.OrderDate,
       o.Status,
       o.TotalAmount
FROM customerorders o
    LEFT JOIN customers c ON o.CustomerID = c.CustomerID;

-- ---------------------------------------------------------------------
-- 2. Пользовательская функция (FUNCTION): сумма заказа по его позициям
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_order_total;
DELIMITER //
CREATE FUNCTION fn_order_total(p_order_id INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(10,2);
    SELECT COALESCE(SUM(d.Quantity * m.Price), 0)
      INTO v_total
      FROM orderdetails d
      JOIN menu m ON d.MenuID = m.MenuID
     WHERE d.OrderID = p_order_id;
    RETURN v_total;
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. Триггер (TRIGGER): автопересчёт суммы заказа при добавлении позиции
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_recalc_total;
DELIMITER //
CREATE TRIGGER trg_recalc_total
AFTER INSERT ON orderdetails
FOR EACH ROW
BEGIN
    UPDATE customerorders
       SET TotalAmount = fn_order_total(NEW.OrderID)
     WHERE OrderID = NEW.OrderID;
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. Хранимая процедура (PROCEDURE): оплата заказа.
--    Демонстрирует транзакцию, локальные переменные, условие и
--    обработчик исключений.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_pay_order;
DELIMITER //
CREATE PROCEDURE sp_pay_order(
    IN  p_order_id INT,
    IN  p_method   ENUM('Cash','Card','Online'),
    OUT p_result   VARCHAR(50))
BEGIN
    DECLARE v_total  DECIMAL(10,2);
    DECLARE v_paid   INT DEFAULT 0;
    DECLARE v_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'Ошибка: платёж отменён';
    END;

    START TRANSACTION;
        SELECT Status INTO v_status
          FROM customerorders WHERE OrderID = p_order_id;
        SELECT COUNT(*) INTO v_paid
          FROM payments WHERE OrderID = p_order_id;

        IF v_status = 'Cancelled' OR v_paid > 0 THEN
            SET p_result = 'Оплата невозможна';
            ROLLBACK;
        ELSE
            SET v_total = fn_order_total(p_order_id);
            INSERT INTO payments(OrderID, Amount, PaymentMethod)
            VALUES (p_order_id, v_total, p_method);
            UPDATE customerorders SET Status = 'Completed'
             WHERE OrderID = p_order_id;
            COMMIT;
            SET p_result = 'Оплачено';
        END IF;
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. Роли и разграничение доступа
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'coffee_admin', 'coffee_cashier';

-- администратор: полный доступ ко всей базе
GRANT ALL PRIVILEGES ON coffee_shop_db.* TO 'coffee_admin';

-- кассир: только то, что нужно для работы с заказами
GRANT SELECT ON coffee_shop_db.menu TO 'coffee_cashier';
GRANT SELECT, INSERT, UPDATE ON coffee_shop_db.customerorders TO 'coffee_cashier';
GRANT SELECT, INSERT ON coffee_shop_db.orderdetails TO 'coffee_cashier';
GRANT EXECUTE ON PROCEDURE coffee_shop_db.sp_pay_order TO 'coffee_cashier';

-- пример: создать пользователя-кассира и выдать ему роль
-- CREATE USER 'cashier1'@'localhost' IDENTIFIED BY 'change_me';
-- GRANT 'coffee_cashier' TO 'cashier1'@'localhost';
